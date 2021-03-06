defmodule Tablespoon.Transport.TCP do
  @moduledoc """
  Transport for sending/receiving bytes over TCP.

  To use:

  tcp = TCP.new(host: host, port: port)
  {:ok, tcp} = UDP.send(tcp, "packet")
  receive do
    x ->
      {:ok, tcp, results} = TCP.stream(tcp, x)
  end
  """
  require Logger
  @behaviour Tablespoon.Transport

  @tcp_opts [:binary, {:active, true}, {:nodelay, true}, {:keepalive, true}]
  @connect_timeout 5_000

  @enforce_keys [:host, :port]
  defstruct @enforce_keys ++ [:socket]

  @impl Tablespoon.Transport
  def new(opts) do
    opts = Keyword.update!(opts, :host, &:erlang.binary_to_list/1)
    struct!(__MODULE__, opts)
  end

  @impl Tablespoon.Transport
  def connect(%__MODULE__{} = tcp) do
    if tcp.socket do
      _ = :gen_tcp.close(tcp.socket)
    end

    with {:ok, socket} <-
           :gen_tcp.connect(
             tcp.host,
             tcp.port,
             @tcp_opts,
             @connect_timeout
           ) do
      tcp = %{tcp | socket: socket}
      {:ok, tcp}
    end
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{socket: socket} = tcp, packet) when is_port(socket) do
    with :ok <- :gen_tcp.send(tcp.socket, packet) do
      {:ok, tcp}
    end
  end

  @impl Tablespoon.Transport
  def stream(%__MODULE__{socket: socket} = tcp, {:tcp, socket, packet}) do
    {:ok, tcp, [data: packet]}
  end

  def stream(%__MODULE__{socket: socket} = tcp, {:tcp_error, socket, error}) do
    _ = Logger.warn("unexpected TCP error socket=#{inspect(socket)} error=#{inspect(error)}")
    # treat it as a closed connection
    stream(tcp, {:tcp_closed, socket})
  end

  def stream(%__MODULE__{socket: socket} = tcp, {:tcp_closed, socket}) do
    :ok = :gen_tcp.close(socket)
    tcp = %{tcp | socket: nil}
    {:ok, tcp, [:closed]}
  end

  def stream(%__MODULE__{}, _) do
    :unknown
  end
end
