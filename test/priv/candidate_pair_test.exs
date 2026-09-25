defmodule ExICE.Priv.CandidatePairTest do
  use ExUnit.Case, async: true

  alias ExICE.Priv.{Candidate, CandidatePair}

  test "new/3" do
    addr1 = {192, 168, 1, 1}
    port1 = 12_345

    c1 =
      Candidate.Host.new(
        address: addr1,
        port: port1,
        base_address: addr1,
        base_port: port1,
        priority: 100,
        socket: nil,
        transport_module: ExICE.Support.Transport.Mock
      )

    addr2 = {192, 168, 1, 2}
    port2 = 23_456

    c2 =
      ExICE.Candidate.new(:host,
        address: addr2,
        port: port2,
        base_address: addr2,
        base_port: port2,
        priority: 200
      )

    c1c2 = CandidatePair.new(c1, c2, :controlling, :frozen)
    assert c1c2.priority == 429_496_730_000

    c2c1 = CandidatePair.new(c1, c2, :controlled, :frozen)
    assert c2c1.priority == 429_496_730_001

    assert abs(c1c2.priority - c2c1.priority) == 1
  end

  test "the keepalive interval spans 4-6 s" do
    # RFC 7675, sec. 5.1: 0.8 to 1.2 times the 5 s base, never under 4 s
    assert CandidatePair.keepalive_interval(0.0) == 4_000
    assert CandidatePair.keepalive_interval(0.5) == 5_000
    assert CandidatePair.keepalive_interval(0.9999) == 6_000

    pair = %CandidatePair{id: 1, local_cand_id: 1, remote_cand_id: 2, priority: 1}

    intervals =
      for _ <- 1..100 do
        %CandidatePair{keepalive_timer: timer} = CandidatePair.schedule_keepalive(pair)
        interval = Process.read_timer(timer)
        Process.cancel_timer(timer)
        interval
      end

    assert Enum.all?(intervals, &(&1 in 3_900..6_000))
    assert Enum.max(intervals) - Enum.min(intervals) > 1_000
  end
end
