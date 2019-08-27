defmodule Tablespoon.IntersectionTest do
  @moduledoc false
  use ExUnit.Case
  alias Tablespoon.Communicator.Modem
  alias Tablespoon.{Intersection, Intersection.Config, Query}
  alias Tablespoon.Transport.FakeModem
  import ExUnit.CaptureLog

  @alias "test_alias"
  @config %Config{
    id: "test_id",
    alias: @alias,
    warning_timeout_ms: 60_000,
    warning_not_before_time: {7, 0, 0},
    warning_not_after_time: {23, 0, 0},
    communicator: Modem.new(FakeModem.new())
  }

  setup do
    {:ok, _pid} = Intersection.start_link(@config)
    :ok
  end

  describe "send_query/1" do
    setup do
      log_level = Logger.level()

      on_exit(fn ->
        Logger.configure(level: log_level)
      end)

      Logger.configure(level: :info)
      :ok
    end

    test "logs the query" do
      query =
        Query.new(
          id: "test_query_id",
          type: :cancel,
          intersection_alias: @alias,
          approach: :south,
          vehicle_id: "vehicle_id",
          event_time: 0
        )

      log =
        capture_log(fn ->
          :ok = Intersection.send_query(query)
          :ok = Intersection.flush(@alias)
        end)

      assert log =~ "Query - id=test_id alias=test_alias comm=Modem"
      assert log =~ "type=cancel"
      assert log =~ "v_id=vehicle_id"
      assert log =~ "approach=south"
      assert log =~ "event_time=1970-01-01T00:00:00Z"
    end

    test "logs the response" do
      query =
        Query.new(
          id: "test_response_id",
          type: :request,
          intersection_alias: @alias,
          approach: :north,
          vehicle_id: "vehicle_id",
          event_time: 0
        )

      log =
        capture_log(fn ->
          :ok = Intersection.send_query(query)
          Process.sleep(10)
          :ok = Intersection.flush(@alias)
        end)

      assert log =~ "Response - id=test_id alias=test_alias comm=Modem"
      assert log =~ "type=request"
      assert log =~ "v_id=vehicle_id"
      assert log =~ "approach=north"
      assert log =~ "event_time=1970-01-01T00:00:00Z"
      assert log =~ "processing_time_us="
    end
  end

  describe "handle_info(:timeout)" do
    setup do
      {:ok, state, _timeout} = Intersection.init(@config)
      {:ok, state: state}
    end

    test "logs a warning during the timeframe", %{state: state} do
      state = %{state | time_fn: fn -> {12, 0, 0} end}

      log =
        capture_log(fn ->
          assert Intersection.handle_info(:timeout, state) ==
                   {:noreply, state, state.config.warning_timeout_ms}
        end)

      assert log =~ "not received"
    end

    test "does not log a warning before the timeframe", %{state: state} do
      state = %{state | time_fn: fn -> {6, 0, 0} end}

      log =
        capture_log(fn ->
          Intersection.handle_info(:timeout, state)
        end)

      assert log == ""
    end

    test "does not log a warning after the timeframe", %{state: state} do
      state = %{state | time_fn: fn -> {23, 50, 0} end}

      log =
        capture_log(fn ->
          Intersection.handle_info(:timeout, state)
        end)

      assert log == ""
    end
  end
end
