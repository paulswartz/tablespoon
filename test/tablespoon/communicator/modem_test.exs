defmodule Tablespoon.Communicator.ModemTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias __MODULE__.FakeTransport
  alias Tablespoon.Communicator.Modem
  alias Tablespoon.Query

  describe "send/2" do
    test "sends a query and acknowledges" do
      query =
        Query.new(
          id: 1,
          type: :request,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm = Modem.new(FakeTransport.new())
      {:ok, comm} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, query)
      {:ok, comm, events} = process_data(comm, ["OK", "\r", "\r\n", "\r\n", "OK\r\n"], events)
      assert events == [{:sent, query}]
      assert comm.transport.sent == ["AT*RELAYOUT4=1\n"]
    end

    test "handles errors in the response" do
      query =
        Query.new(
          id: 1,
          type: :request,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm = Modem.new(FakeTransport.new())
      {:ok, comm} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, query)
      {:ok, _comm, events} = process_data(comm, ["OK\n", "ERROR\n"], events)
      assert events == [{:failed, query, :error}]
    end

    test "acks queries in FIFO order" do
      request =
        Query.new(
          id: 1,
          type: :request,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      cancel =
        Query.new(
          id: 1,
          type: :cancel,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm = Modem.new(FakeTransport.new())
      {:ok, comm} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, request)
      {:ok, comm, events2} = Modem.send(comm, cancel)
      {:ok, comm, events} = process_data(comm, ["OK\nOK\nOK\n"], events ++ events2)
      assert comm.transport.sent == ["AT*RELAYOUT4=1\n", "AT*RELAYOUT4=0\n"]
      assert events == [{:sent, request}, {:sent, cancel}]
    end

    test "does not send an extra cancel if two vehicles request TSP" do
      vehicle_ids = ["1", "2"]

      queries =
        for type <- [:request, :cancel],
            vehicle_id <- vehicle_ids do
          Query.new(
            id: :erlang.unique_integer([:monotonic]),
            type: type,
            vehicle_id: vehicle_id,
            intersection_alias: "int",
            approach: :north,
            event_time: System.system_time()
          )
        end

      comm = Modem.new(FakeTransport.new())
      {:ok, comm} = Modem.connect(comm)

      {:ok, comm, events} =
        Enum.reduce(queries, {:ok, comm, []}, fn q, {:ok, comm, events} ->
          {:ok, comm, new_events} = Modem.send(comm, q)
          {:ok, comm, events ++ new_events}
        end)

      {:ok, comm, events} = process_data(comm, ["OK\nOK\nOK\nOK\n"], events)
      assert comm.transport.sent == ["AT*RELAYOUT2=1\n", "AT*RELAYOUT2=1\n", "AT*RELAYOUT2=0\n"]
      assert [sent: _, sent: _, sent: _, sent: _] = events
    end
  end

  defp process_data(comm, datas, events) do
    Enum.reduce_while(datas, {:ok, comm, events}, fn data, {:ok, comm, events} ->
      case Modem.stream(comm, data) do
        {:ok, comm, new_events} ->
          {:cont, {:ok, comm, events ++ new_events}}

        other ->
          {:halt, other}
      end
    end)
  end

  defmodule FakeTransport do
    @moduledoc false
    @behaviour Tablespoon.Transport
    defstruct connected?: false, sent: []

    @impl Tablespoon.Transport
    def new(_opts \\ []) do
      %__MODULE__{}
    end

    @impl Tablespoon.Transport
    def connect(fake) do
      {:ok, %{fake | connected?: true}}
    end

    @impl Tablespoon.Transport
    def send(%__MODULE__{connected?: true} = fake, iodata) do
      binary = IO.iodata_to_binary(iodata)
      {:ok, %{fake | sent: fake.sent ++ [binary]}}
    end

    def send(_fake, _) do
      {:error, :not_connected}
    end

    @impl Tablespoon.Transport
    def stream(%__MODULE__{connected?: true} = fake, binary) do
      {:ok, fake, [data: binary]}
    end

    def stream(fake, _message) do
      {:ok, fake, []}
    end
  end
end