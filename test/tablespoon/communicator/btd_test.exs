defmodule Tablespoon.Communicator.BtdTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tablespoon.Communicator.Btd
  import Btd
  doctest Tablespoon.Communicator.Btd

  alias Tablespoon.Protocol.NTCIP1211Extended, as: NTCIP
  alias Tablespoon.Protocol.PMPP
  alias Tablespoon.Query
  alias Tablespoon.Transport.Fake, as: FakeTransport

  @group "group"
  @address 12
  @intersection_id 1234

  describe "send/2" do
    test "sends a PMPP/NTCIP1211 request query and receives an ack" do
      query =
        Query.new(
          id: 1,
          type: :request,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm =
        Btd.new(
          FakeTransport.new(),
          group: @group,
          address: @address,
          intersection_id: @intersection_id
        )

      {:ok, comm} = Btd.connect(comm)
      {:ok, comm, []} = Btd.send(comm, query)

      ntcip_message = %NTCIP.PriorityRequest{
        id: 1,
        vehicle_id: "1",
        vehicle_class: 2,
        vehicle_class_level: 0,
        strategy: 3,
        time_of_service_desired: 0,
        time_of_estimated_departure: 0,
        intersection_id: @intersection_id
      }

      ntcip =
        NTCIP.encode(%NTCIP{
          group: @group,
          pdu_type: :response,
          request_id: 0,
          message: ntcip_message
        })

      pmpp = PMPP.encode(%PMPP{address: @address, control: :information_poll, body: ntcip})

      {:ok, comm, [sent: ^query]} = Btd.stream(comm, pmpp)
      [sent_packet] = comm.transport.sent

      assert {:ok, %PMPP{address: @address, control: :information_poll, body: ntcip_body}, ""} =
               PMPP.decode(sent_packet)

      assert {:ok, %NTCIP{group: @group, pdu_type: :set, request_id: 0, message: ^ntcip_message}} =
               NTCIP.decode(ntcip_body)
    end

    test "sends a PMPP/NTCIP1211 cancel query and receives an ack" do
      query =
        Query.new(
          id: 1,
          type: :cancel,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm =
        Btd.new(
          FakeTransport.new(),
          group: @group,
          address: @address,
          intersection_id: @intersection_id
        )

      {:ok, comm} = Btd.connect(comm)
      {:ok, comm, []} = Btd.send(comm, query)

      ntcip_message = %NTCIP.PriorityCancel{
        id: 1,
        vehicle_id: "1",
        vehicle_class: 2,
        vehicle_class_level: 0,
        strategy: 3
      }

      ntcip =
        NTCIP.encode(%NTCIP{
          group: @group,
          pdu_type: :response,
          request_id: 0,
          message: ntcip_message
        })

      pmpp = PMPP.encode(%PMPP{address: @address, control: :information_poll, body: ntcip})

      {:ok, comm, [sent: ^query]} = Btd.stream(comm, pmpp)
      [sent_packet] = comm.transport.sent

      assert {:ok, %PMPP{address: @address, control: :information_poll, body: ntcip_body}, ""} =
               PMPP.decode(sent_packet)

      assert {:ok, %NTCIP{group: @group, pdu_type: :set, request_id: 0, message: ^ntcip_message}} =
               NTCIP.decode(ntcip_body)
    end
  end

  describe "stream/2" do
    test "reconnects if the transport closes the connection" do
      comm =
        Btd.new(
          FakeTransport.new(),
          group: @group,
          address: @address,
          intersection_id: @intersection_id
        )

      {:ok, comm} = Btd.connect(comm)
      {:ok, comm, []} = Btd.stream(comm, :close)
      assert comm.transport.connect_count == 2
    end

    property "always returns a response" do
      check all query_responses <- list_of({query(), response()}, min_length: 1) do
        comm =
          Btd.new(
            FakeTransport.new(),
            group: @group,
            address: @address,
            intersection_id: @intersection_id,
            timeout: 0
          )

        {:ok, comm} = Btd.connect(comm)

        {:ok, _comm, events} =
          Enum.reduce(query_responses, {:ok, comm, []}, fn {query, response},
                                                           {:ok, comm, events} ->
            {:ok, comm, send_events} = Btd.send(comm, query)
            {:ok, comm, stream_events} = Btd.stream(comm, stream_response(comm, response))
            {:ok, comm, receive_events} = maybe_receive_events(comm, [])
            {:ok, comm, events ++ send_events ++ stream_events ++ receive_events}
          end)

        assert length(events) == length(query_responses)

        for {{query, _response}, event} <- Enum.zip(query_responses, events) do
          assert elem(event, 0) in [:sent, :failed]
          assert elem(event, 1) == query
        end
      end
    end
  end

  defp maybe_receive_events(comm, events) do
    receive do
      x ->
        case Btd.stream(comm, x) do
          :unknown ->
            maybe_receive_events(comm, events)

          {:ok, comm, new_events} ->
            maybe_receive_events(comm, events ++ new_events)
        end
    after
      0 ->
        {:ok, comm, events}
    end
  end

  defp stream_response(comm, :succeed) do
    data = List.last(comm.transport.sent)
    {:ok, pmpp, ""} = PMPP.decode(IO.iodata_to_binary(data))
    {:ok, ntcip} = NTCIP.decode(pmpp.body)
    ntcip_response = NTCIP.encode(%{ntcip | pdu_type: :response})
    IO.iodata_to_binary(PMPP.encode(%{pmpp | body: ntcip_response}))
  end

  defp stream_response(_comm, :drop) do
    :empty
  end

  defp stream_response(_comm, :invalid) do
    IO.iodata_to_binary(
      PMPP.encode(%PMPP{address: @address, control: :information_poll, body: ""})
    )
  end

  defp stream_response(_comm, :close) do
    :close
  end

  defp query do
    gen all type <- one_of([:request, :cancel]),
            approach <- one_of([:north, :east, :south, :west]) do
      Query.new(
        id: 1,
        type: type,
        vehicle_id: "1",
        intersection_alias: "int",
        approach: approach,
        event_time: System.system_time()
      )
    end
  end

  defp response do
    one_of([:succeed, :drop, :invalid, :close])
  end
end
