/* React congestion control */

#include <linux/module.h>
#include <net/tcp.h>
#include <linux/win_minmax.h>

#define BW_SCALE 24

#define REACT_SCALE 8
#define REACT_UNIT (1 << REACT_SCALE)

#define REACT_INIT_CWND 25

#define DO_CONDITIONAL_OPT(a, b, c) ((c) ^ ((!(a) - 1) & ((b) ^ (c))))

#define REACT_MIN(a, b) DO_CONDITIONAL_OPT((a) < (b), a, b)
#define REACT_MAX(a, b) DO_CONDITIONAL_OPT((a) > (b), a, b)
#define REACT_MAX3(a, b, c) REACT_MAX(REACT_MAX(a, b), c)

#define REACT_SGN32(x) -(-((x) >> 31) | (-(x) >> 31))

/* window length of min_rtt filter (in sec): */
static const u32 react_min_rtt_win_sec = 10;

static const int react_high_gain = REACT_UNIT * 2885 / 1000 + 1;
static const int react_drain_gain = REACT_UNIT * 3 / 4;
static const int react_cwnd_gain = REACT_UNIT * 2;
static const int react_probe_gain = REACT_UNIT * 3 / 2;

static const u8 react_full_bw_cnt = 3;

/* sampling windows size react_grad used for smoothing moving: */
static unsigned int window __read_mostly = 4;
/* Window length of bw filter (in rounds): */
static unsigned int react_bw_rtts __read_mostly = 15;

module_param(window, int, 0444);
MODULE_PARM_DESC(window, "gradient window size (power of two <= 256)");
module_param(react_bw_rtts, uint, 0644);
MODULE_PARM_DESC(react_bw_rtts, "window length of bw filter (in rounds)");

struct cdg_minmax {
	union {
		struct {
			s32 min;
			s32 max;
		};
		u64 v64;
	};
};

enum react_state {
	CDG_UNKNOWN = 0,
	CDG_NONFULL = 1,
	CDG_FULL = 2
};

/* React congestion control block */
struct react {
	struct cdg_minmax rtt;
	struct cdg_minmax rtt_prev;
	struct cdg_minmax *gradients;
	struct cdg_minmax gsum;
	struct minmax bw;	/* Max recent delivery rate in pkts/uS << 24 */
	u32 cwnd_gain,
		pacing_gain,
		min_rtt_us,	        /* min RTT in min_rtt_win_sec window */
		rtt_seq,
		min_rtt_stamp,	        /* timestamp of min_rtt_us */
		next_rtt_delivered; /* scb->tx.delivered at end of round */
	u16 rtt_cnt;	    /* count of packet-timed rounds elapsed */
	u8  tail,
		state,
		full_bw_cnt;
	bool drain_queue,
		round_restart,
		packet_conservation;
};

static inline u32 react_max_bw(struct react *ca)
{
	return minmax_get(&ca->bw);
}

static inline u64 react_rate_bytes_per_sec(struct sock *sk, u64 rate, int gain)
{
	rate *= tcp_mss_to_mtu(sk, tcp_sk(sk)->mss_cache);
	rate *= gain;
	rate >>= REACT_SCALE;
	rate *= USEC_PER_SEC;
	return rate >> BW_SCALE;
}

static inline void react_set_pacing_rate(struct sock *sk, u64 bw, int gain)
{
	u64 rate = bw;

	rate = react_rate_bytes_per_sec(sk, rate, gain);
	rate = REACT_MIN(rate, sk->sk_max_pacing_rate);
	sk->sk_pacing_rate = REACT_MAX(rate, sk->sk_pacing_rate);
}

/* Find target cwnd. Right-size the cwnd based on min RTT and the
* estimated bottleneck bandwidth:
*
* cwnd = bw * min_rtt * gain = BDP * gain
*
* The key factor, gain, controls the amount of queue. While a small gain
* builds a smaller queue, it becomes more vulnerable to noise in RTT
* measurements (e.g., delayed ACKs or other ACK compression effects). This
* noise may cause BBR to under-estimate the rate.
*/

static u32 react_target_cwnd(struct sock *sk, struct react *ca, int gain)
{
	u64 w;
	u32 bw, cwnd;

	if (unlikely(ca->min_rtt_us == ~0U))	 /* no valid RTT samples yet? */
		return REACT_INIT_CWND;  /* be safe: cap at default initial cwnd */

	bw = react_max_bw(ca);

	w = (u64)bw * ca->min_rtt_us;

	cwnd = ((w * gain) >> (BW_SCALE + REACT_SCALE)) + 18;

	/* Reduce delayed ACKs by rounding up cwnd to the next even number. */
	cwnd = (cwnd + 1) & ~1U;

	return cwnd;
}

static inline void react_set_cwnd(struct sock *sk, const struct rate_sample *rs, int gain)
{
	struct tcp_sock *tp = tcp_sk(sk);
	struct react *ca = inet_csk_ca(sk);
	u32 cwnd = tp->snd_cwnd, target_cwnd;

	target_cwnd = DO_CONDITIONAL_OPT(ca->packet_conservation, REACT_MAX(cwnd, tcp_packets_in_flight(tp) + rs->acked_sacked), react_target_cwnd(sk, ca, gain));

	cwnd = REACT_MAX(target_cwnd, 4);

	tp->snd_cwnd = REACT_MIN(cwnd, tp->snd_cwnd_clamp);
	tp->rcv_ssthresh = TCP_INFINITE_SSTHRESH;
	tp->rcv_wnd = REACT_MAX(cwnd, tp->rcv_wnd);

	ca->packet_conservation = 0;
}


static void react_check_drain(struct sock *sk, const struct rate_sample *rs, struct react *ca)
{
	bool non_cong = (ca->state != CDG_FULL);

	if (!ca->drain_queue && !ca->round_restart) {
		struct tcp_sock *tp = tcp_sk(sk);
		u32 inflight = REACT_MIN(tcp_packets_in_flight(tp), rs->prior_in_flight);
		ca->cwnd_gain = DO_CONDITIONAL_OPT(non_cong, react_high_gain, react_cwnd_gain);
		if (inflight < tp->snd_cwnd)
			ca->pacing_gain = DO_CONDITIONAL_OPT(non_cong, react_high_gain, react_probe_gain);
		else
			ca->pacing_gain = DO_CONDITIONAL_OPT(non_cong, react_probe_gain, REACT_UNIT);
	}
	else if (ca->drain_queue && !ca->round_restart) {
		ca->cwnd_gain = react_high_gain;
		ca->pacing_gain = DO_CONDITIONAL_OPT(non_cong, REACT_UNIT, react_drain_gain);
		ca->state = CDG_UNKNOWN;
		ca->packet_conservation = 1;
	}
	ca->round_restart = 0;
}

/* We use the delay gradient as a congestion signal. */
static void react_grad(struct react *ca)
{
	s32 gmin = ca->rtt.min - ca->rtt_prev.min;
	s32 gmax = ca->rtt.max - ca->rtt_prev.max;

	if (ca->gradients) {
		ca->gsum.min += gmin - ca->gradients[ca->tail].min;
		ca->gsum.max += gmax - ca->gradients[ca->tail].max;
		ca->gradients[ca->tail].min = gmin;
		ca->gradients[ca->tail].max = gmax;
		ca->tail = (ca->tail + 1) & (window - 1);
		gmin = ca->gsum.min;
		gmax = ca->gsum.max;
	}

	gmin += 32;
	gmax += 32;

	if (gmin > 0 && gmax <= 0)
		ca->state = CDG_FULL;
	else if ((gmin > 0 && gmax > 0) || gmax < 0) {
		ca->state = CDG_NONFULL;
		ca->full_bw_cnt = 0;
	}
}

static void react_update_rtt_grad(struct sock *sk, const struct rate_sample *rs, struct react *ca)
{
	if (likely(rs->rtt_us)) {
		ca->rtt.min = REACT_MIN(DO_CONDITIONAL_OPT(ca->rtt.min > 0, ca->rtt.min, 1), rs->rtt_us);
		ca->rtt.max = REACT_MAX(ca->rtt.max, rs->rtt_us);
	}

	if (after(tcp_sk(sk)->snd_una, ca->rtt_seq + 1) && ca->rtt.v64) {
		if (ca->rtt_prev.v64)
			react_grad(ca);
		ca->rtt_seq = tcp_sk(sk)->snd_nxt;
		ca->rtt_prev = ca->rtt;
		ca->rtt.v64 = 0;
	}
}

static void react_update_min_rtt(struct sock *sk, const struct rate_sample *rs, struct react *ca)
{
	bool filter_expired;

	/* Track min RTT seen in the min_rtt_win_sec filter window: */
	filter_expired = after(tcp_time_stamp,
		ca->min_rtt_stamp + react_min_rtt_win_sec * HZ);
	if (rs->rtt_us >= 0 &&
		(rs->rtt_us <= ca->min_rtt_us || filter_expired)) {
		ca->min_rtt_us = rs->rtt_us;
		ca->min_rtt_stamp = tcp_time_stamp;
	}

	ca->drain_queue = (filter_expired || (ca->state == CDG_FULL && ca->full_bw_cnt >= react_full_bw_cnt));
}

static void react_update_bw(struct sock *sk, const struct rate_sample *rs, struct react *ca)
{
	u64 bw, bw_thresh;

	if (rs->delivered < 0 || rs->interval_us <= 0)
		return; /* Not a valid observation */

				/* See if we've reached the next RTT */
	if (!before(rs->prior_delivered, ca->next_rtt_delivered)) {
		ca->next_rtt_delivered = tcp_sk(sk)->delivered;
		ca->rtt_cnt++;
	}

	/* Divide delivered by the interval to find a (lower bound) bottleneck
	* bandwidth sample. Delivered is in packets and interval_us in uS and
	* ratio will be <<1 for most connections. So delivered is first scaled.
	*/
	bw = ((u64)rs->delivered << BW_SCALE);
	do_div(bw, rs->interval_us);

	bw_thresh = (((u64)react_max_bw(ca) >> 3) * 9);

	++ca->full_bw_cnt;
	if (bw >= bw_thresh) {
		ca->full_bw_cnt = 0;
		ca->state = CDG_UNKNOWN;
	}

	ca->full_bw_cnt = REACT_MIN(ca->full_bw_cnt, react_full_bw_cnt);

	/* If this sample is application-limited, it is likely to have a very
	* low delivered count that represents application behavior rather than
	* the available network rate. Such a sample could drag down estimated
	* bw, causing needless slow-down. Thus, to continue to send at the
	* last measured network rate, we filter out app-limited samples unless
	* they describe the path bw at least as well as our bw model.
	*
	* So the goal during app-limited phase is to proceed with the best
	* network rate no matter how long. We automatically leave this
	* phase when app writes faster than the network can deliver :)
	*/
	if (!rs->is_app_limited || bw >= react_max_bw(ca)) {
		/* Incorporate new sample into our max bw filter. */
		minmax_running_max(&ca->bw, react_bw_rtts, (u32)ca->rtt_cnt, bw);
	}
}


static inline void react_update_model(struct sock *sk, const struct rate_sample *rs, struct react *ca)
{
	react_update_bw(sk, rs, ca);
	react_update_min_rtt(sk, rs, ca);
	react_update_rtt_grad(sk, rs, ca);
	react_check_drain(sk, rs, ca);
}

static void react_main(struct sock *sk, const struct rate_sample *rs)
{
	struct react *ca = inet_csk_ca(sk);

	react_update_model(sk, rs, ca);

	react_set_cwnd(sk, rs, ca->cwnd_gain);
	react_set_pacing_rate(sk, react_max_bw(ca), ca->pacing_gain);
}

static void react_set_state(struct sock *sk, u8 new_state)
{
	struct react *ca = inet_csk_ca(sk);

	switch (new_state) {
	case TCP_CA_Loss:
		if (ca->state != CDG_FULL)
			/* Reset zero-window probe timer to push pending frames. */
			inet_csk_reset_xmit_timer(sk, ICSK_TIME_PROBE0,
				tcp_probe0_base(sk), TCP_RTO_MAX);
		ca->round_restart = 1;
		ca->pacing_gain = react_high_gain;
		ca->full_bw_cnt = 0;
		break;
	case TCP_CA_Recovery:
		if (ca->state != CDG_NONFULL) {
			ca->packet_conservation = 1;
			ca->next_rtt_delivered = tcp_sk(sk)->delivered;
		}
		break;
	default:
		break;
	}
}

static void react_init(struct sock *sk)
{
	struct react *ca = inet_csk_ca(sk);
	struct tcp_sock *tp = tcp_sk(sk);

	/* We silently fall back to window = 1 if allocation fails. */
	ca->gradients = kcalloc(window, sizeof(ca->gradients[0]),
		GFP_NOWAIT | __GFP_NOWARN);
	ca->rtt_seq = tp->snd_nxt;

	ca->min_rtt_stamp = tcp_time_stamp;
	ca->min_rtt_us = tcp_min_rtt(tp);

	ca->state = CDG_NONFULL;

	ca->full_bw_cnt = 0;

	ca->rtt_cnt = 0;
	ca->next_rtt_delivered = 0;

	ca->round_restart = 1;
	ca->packet_conservation = 0;

	ca->pacing_gain = react_high_gain;
	ca->cwnd_gain = react_high_gain;

	minmax_reset(&ca->bw, (u32)ca->rtt_cnt, 0);  /* init max bw to 0 */
}

static void react_cwnd_event(struct sock *sk, const enum tcp_ca_event ev)
{
	struct react *ca = inet_csk_ca(sk);
	struct cdg_minmax *gradients;

	switch (ev) {
	case CA_EVENT_TX_START:
		ca->state = CDG_NONFULL;
		ca->pacing_gain = react_high_gain;
		ca->cwnd_gain = react_high_gain;
		ca->round_restart = 1;
		break;
	case CA_EVENT_CWND_RESTART:
		gradients = ca->gradients;
		if (gradients)
			memset(gradients, 0, window * sizeof(gradients[0]));
		memset(ca, 0, sizeof(*ca));
		ca->state = CDG_UNKNOWN;
		ca->gradients = gradients;
		ca->rtt_seq = tcp_sk(sk)->snd_nxt;
		break;
	default:
		break;
	}
}

static u32 react_undo_cwnd(struct sock *sk)
{
	return tcp_sk(sk)->snd_cwnd;
}

static void react_release(struct sock *sk)
{
	struct react *ca = inet_csk_ca(sk);

	kfree(ca->gradients);
}

static u32 react_sndbuf_expand(struct sock *sk)
{
	return 3;
}

static u32 react_ssthresh(struct sock *sk)
{
	return TCP_INFINITE_SSTHRESH;
}

static struct tcp_congestion_ops react_cong_ops __read_mostly = {
	.flags = TCP_CONG_NON_RESTRICTED,
	.name = "react_rc2",
	.owner = THIS_MODULE,
	.init = react_init,
	.cong_control = react_main,
	.cwnd_event = react_cwnd_event,
	.release = react_release,
	.sndbuf_expand = react_sndbuf_expand,
	.undo_cwnd = react_undo_cwnd,
	.ssthresh = react_ssthresh,
	.set_state = react_set_state,
};

static int __init react_register(void)
{
	BUILD_BUG_ON(sizeof(struct react) > ICSK_CA_PRIV_SIZE);
	return tcp_register_congestion_control(&react_cong_ops);
}

static void __exit react_unregister(void)
{
	tcp_unregister_congestion_control(&react_cong_ops);
}

module_init(react_register);
module_exit(react_unregister);

MODULE_AUTHOR("Neal Cardwell <ncardwell@google.com>");
MODULE_AUTHOR("Yuchung Cheng <ycheng@google.com>");
MODULE_AUTHOR("Kenneth Klette Jonassen");
MODULE_LICENSE("Dual BSD/GPL");
MODULE_DESCRIPTION("TCP React");