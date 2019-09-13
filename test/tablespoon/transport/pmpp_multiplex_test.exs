defmodule Tablespoon.Transport.PMPPMultiplexTest do
  @moduledoc false
  use ExUnit.Case

  alias Tablespoon.Transport.PMPPMultiplex

  describe "send + stream" do
    test "receives an echo message" do
      t = PMPPMultiplex.new(transport: Echo.new(), address: 2)
      {:ok, t} = PMPPMultiplex.connect(t)
      message = test_message()
      {:ok, t} = PMPPMultiplex.send(t, message)

      receive do
        x ->
          assert {:ok, %PMPPMultiplex{}, [{:data, ^message}]} = PMPPMultiplex.stream(t, x)
      end
    end

    test "two different transports receive different messages" do
      transport = Echo.new()
      t = PMPPMultiplex.new(transport: transport, address: 3)
      t2 = PMPPMultiplex.new(transport: transport, address: 3)
      {:ok, t} = PMPPMultiplex.connect(t)
      {:ok, t2} = PMPPMultiplex.connect(t2)

      # different refs, same PID
      refute t.from == t2.from
      assert elem(t.from, 0) == elem(t2.from, 0)

      message = test_message()
      message2 = test_message()
      {:ok, t} = PMPPMultiplex.send(t, message)
      {:ok, t2} = PMPPMultiplex.send(t2, message2)

      receive do
        x ->
          assert {:ok, %PMPPMultiplex{}, [{:data, ^message}]} = PMPPMultiplex.stream(t, x)
      end

      receive do
        x ->
          assert {:ok, %PMPPMultiplex{}, [{:data, ^message2}]} = PMPPMultiplex.stream(t2, x)
      end
    end

    test "closing the child returns a closed message" do
      t = PMPPMultiplex.new(transport: Echo.new(), address: 4)
      {:ok, t} = PMPPMultiplex.connect(t)
      # breaking into the struct to get the child we're connected to
      {pid, _} = t.from
      GenServer.stop(pid)

      receive do
        x ->
          assert {:ok, %PMPPMultiplex{}, [:closed]} = PMPPMultiplex.stream(t, x)
      end
    end
  end

  defp test_message do
    Integer.to_string(:erlang.unique_integer())
  end
end

defmodule Echo do
  @moduledoc "Echo transport"
  @behaviour Tablespoon.Transport

  defstruct [:ref]

  @impl Tablespoon.Transport
  def new(_opts \\ []) do
    %__MODULE__{}
  end

  @impl Tablespoon.Transport
  def connect(%__MODULE__{} = t) do
    {:ok, %{t | ref: make_ref()}}
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{ref: ref} = t, iodata) when is_reference(ref) do
    Kernel.send(self(), {ref, {:data, IO.iodata_to_binary(iodata)}})
    {:ok, t}
  end

  def send(%__MODULE__{}, _) do
    {:error, :not_connected}
  end

  @impl Tablespoon.Transport
  def stream(%__MODULE__{ref: ref} = t, {ref, message}) do
    {:ok, t, [message]}
  end
end
