defmodule ExICE.Priv.CandidatePair do
  @moduledoc false

  alias ExICE.Priv.{Candidate, Utils}

  # Tr timeout (keepalives, which are also consent checks) in ms.
  # The actual interval is randomized, see keepalive_interval/1.
  @tr_timeout 5 * 1000

  # Consent expiry in ms.
  # See RFC 7675, sec. 5.1.
  @consent_expiry 30 * 1000

  @type state() :: :waiting | :in_progress | :succeeded | :failed | :frozen

  @type t() :: %__MODULE__{
          id: integer(),
          local_cand_id: integer(),
          nominate?: boolean(),
          nominated?: boolean(),
          priority: non_neg_integer(),
          remote_cand_id: integer(),
          state: state(),
          valid?: boolean,
          succeeded_pair_id: integer() | nil,
          discovered_pair_id: integer() | nil,
          keepalive_timer: reference() | nil,
          last_seen: integer(),
          last_consent: integer() | nil,
          consent_expired?: boolean(),
          packets_sent: non_neg_integer(),
          packets_received: non_neg_integer(),
          bytes_sent: non_neg_integer(),
          bytes_received: non_neg_integer(),
          requests_received: non_neg_integer(),
          requests_sent: non_neg_integer(),
          responses_received: non_neg_integer(),
          non_symmetric_responses_received: non_neg_integer(),
          responses_sent: non_neg_integer(),
          packets_discarded_on_send: non_neg_integer(),
          bytes_discarded_on_send: non_neg_integer()
        }

  @enforce_keys [:id, :local_cand_id, :remote_cand_id, :priority]
  defstruct @enforce_keys ++
              [
                nominate?: false,
                nominated?: false,
                state: :frozen,
                valid?: false,
                succeeded_pair_id: nil,
                discovered_pair_id: nil,
                keepalive_timer: nil,
                # Time when this pair has received some data
                # or sent conn check.
                last_seen: nil,
                # Time when this pair has received an authenticated,
                # symmetric success response to our own binding request
                # (consent to send, RFC 7675).
                last_consent: nil,
                # Whether this pair failed because its consent expired.
                # Such a pair can't be used again until an ICE restart.
                consent_expired?: false,
                packets_sent: 0,
                packets_received: 0,
                bytes_sent: 0,
                bytes_received: 0,
                requests_received: 0,
                requests_sent: 0,
                responses_received: 0,
                non_symmetric_responses_received: 0,
                responses_sent: 0,
                packets_discarded_on_send: 0,
                bytes_discarded_on_send: 0
              ]

  @doc false
  @spec new(Candidate.t(), Candidate.t(), ExICE.ICEAgent.role(), state(), [
          {:valid?, boolean()} | {:last_seen, integer()}
        ]) :: t()
  def new(local_cand, remote_cand, agent_role, state, opts \\ []) do
    priority = priority(agent_role, local_cand.base.priority, remote_cand.priority)

    %__MODULE__{
      id: Utils.id(),
      local_cand_id: local_cand.base.id,
      remote_cand_id: remote_cand.id,
      priority: priority,
      state: state,
      valid?: opts[:valid?] || false,
      last_seen: opts[:last_seen]
    }
  end

  @doc false
  @spec schedule_keepalive(t(), Process.dest()) :: t()
  def schedule_keepalive(pair, dest \\ self())

  def schedule_keepalive(%{keepalive_timer: timer} = pair, dest) when is_reference(timer) do
    Process.cancel_timer(timer)
    schedule_keepalive(%{pair | keepalive_timer: nil}, dest)
  end

  def schedule_keepalive(pair, dest) do
    interval = keepalive_interval(:rand.uniform())
    ref = Process.send_after(dest, {:keepalive_timeout, pair.id}, interval)
    %{pair | keepalive_timer: ref}
  end

  # Keepalive interval for a draw from [0, 1): from 0.8 to 1.2 times Tr.
  # See RFC 7675, sec. 5.1.
  @doc false
  @spec keepalive_interval(float()) :: pos_integer()
  def keepalive_interval(draw) do
    round(@tr_timeout * (0.8 + 0.4 * draw))
  end

  # Whether the pair's consent, if it has any, has expired at `now`.
  @doc false
  @spec consent_timed_out?(t(), integer()) :: boolean()
  def consent_timed_out?(%__MODULE__{last_consent: nil}, _now), do: false

  def consent_timed_out?(%__MODULE__{last_consent: last_consent}, now),
    do: timed_out?(last_consent, now)

  # Whether a response to a keepalive sent at `sent_at` can no longer grant consent at `now`.
  @doc false
  @spec check_timed_out?(integer(), integer()) :: boolean()
  def check_timed_out?(sent_at, now), do: timed_out?(sent_at, now)

  defp timed_out?(time, now), do: now - time >= @consent_expiry

  @doc false
  @spec recompute_priority(t(), integer(), integer(), ExICE.ICEAgent.role()) :: t()
  def recompute_priority(%__MODULE__{} = pair, local_cand_prio, remote_cand_prio, role) do
    %{pair | priority: priority(role, local_cand_prio, remote_cand_prio)}
  end

  @doc false
  @spec priority(ExICE.ICEAgent.role(), integer(), integer()) :: non_neg_integer()
  def priority(:controlling, local_cand_prio, remote_cand_prio) do
    do_priority(local_cand_prio, remote_cand_prio)
  end

  def priority(:controlled, local_cand_prio, remote_cand_prio) do
    do_priority(remote_cand_prio, local_cand_prio)
  end

  defp do_priority(g, d) do
    # refer to RFC 8445 sec. 6.1.2.3
    2 ** 32 * min(g, d) + 2 * max(g, d) + if g > d, do: 1, else: 0
  end

  @doc false
  @spec to_candidate_pair(t()) :: ExICE.CandidatePair.t()
  def to_candidate_pair(pair) do
    %ExICE.CandidatePair{
      id: pair.id,
      local_cand_id: pair.local_cand_id,
      nominated?: pair.nominated?,
      priority: pair.priority,
      remote_cand_id: pair.remote_cand_id,
      state: pair.state,
      valid?: pair.valid?,
      last_seen: pair.last_seen,
      requests_received: pair.requests_received,
      requests_sent: pair.requests_sent,
      responses_received: pair.responses_received,
      non_symmetric_responses_received: pair.non_symmetric_responses_received,
      responses_sent: pair.responses_sent
    }
  end
end
