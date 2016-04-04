defmodule APNS.MessageHandlerTest do
  use ExUnit.Case

  alias APNS.MessageHandler
  alias APNS.FakeSender

  import ExUnit.CaptureLog

  @moduletag :capture_log

  setup do
    state = %{
      config: %{
        callback_module: APNS.Callback,
        payload_limit: 2048,
        reconnect_after: 3,
        apple_host: "host.apple",
        apple_port: 2195,
        timeout: 10
      },
      socket_apple: "socket",
      queue: [],
      counter: 0,
      ssl_opts: %{}
    }
    token = String.duplicate("0", 64)
    message =
      %APNS.Message{}
      |> Map.put(:token, token)
      |> Map.put(:alert, "Lorem ipsum dolor sit amet, consectetur adipisicing elit")
      |> Map.put(:id, 23)

    {:ok, %{
      apple_success_buffer: <<0 :: 8, 0 :: 8, "1337" :: binary>>,
      state: state,
      message: message,
      token: token
    }}
  end

  test "connect calls close before connecting", %{state: state} do
    output = capture_log(fn -> MessageHandler.connect(state, FakeSender) end)
    assert output =~ ~s(APNS.FakeSender.close)
    assert output =~ ~s(APNS.FakeSender.connect_socket)
  end

  test "connect connects to configured host", %{state: state} do
    output = capture_log(fn -> MessageHandler.connect(state, FakeSender) end)
    assert output =~ ~s(APNS.FakeSender.connect_socket/4)
    assert output =~ ~s(host: 'host.apple')
    assert output =~ ~s(port: 2195)
    assert output =~ ~s(opts: %{})
    assert output =~ ~s(timeout: 10)
  end

  test "connect returns ok if connection succeeded", %{state: state} do
    assert {:ok, %{config: %{apple_host: "host.apple"}}} = MessageHandler.connect(state, FakeSender)
  end

  test "connect returns error if connection failed", %{state: state} do
    result = MessageHandler.connect(state, APNS.FakeSenderConnectFail)
    assert result == {:error, {:connection_failed, "host.apple:2195"}}
  end

  test "push calls error callback if token is invalid size", %{state: state, message: message} do
    token = String.duplicate("0", 63)
    message = Map.put(message, :token, token)
    output = capture_log(fn -> MessageHandler.push(message, state) end)
    assert output =~ ~s([APNS] Error "Invalid token size" for message 23 to #{token})
  end

  test "push calls error callback if payload is too big", %{state: state, message: message} do
    state = put_in(state, [:config, :payload_limit], 10)
    output = capture_log(fn -> MessageHandler.push(message, state) end)
    assert output =~ ~s([APNS] Error "Invalid payload size" for message 23)
  end

  @tag :pending # shouldn't this pass? See APNS.Payload.to_json
  test "push calls error callback if payload size can be set per message", %{state: state, message: message} do
    message = Map.put(message, :support_old_ios, true)
    message = Map.put(message, :alert, String.duplicate("0", 2000))
    output = capture_log(fn -> MessageHandler.push(message, state) end)
    assert output =~ ~s([APNS] Error "Invalid payload size" for message 23)
  end

  test "push sends payload to Apple", %{state: state, message: message, token: token} do
    output = capture_log(fn -> MessageHandler.push(message, state, APNS.FakeSender) end)
    assert output =~ ~s(APNS.FakeSender.send_package/2)
    assert output =~ ~s(to #{token})
  end

  test "push clears queue on ssl error", %{state: state, message: message} do
    state = %{state | queue: [1, 2, 3]}
    assert %{queue: []} = MessageHandler.push(message, state, APNS.FakeSenderSendPackageFail)
  end

  test "push logs error on ssl error", %{state: state, message: message} do
    output = capture_log(fn -> MessageHandler.push(message, state, APNS.FakeSenderSendPackageFail) end)
    assert output =~ ~s(APNS.FakeSender.send_package/2)
    assert output =~ ~s/[APNS] error (FakeSenderSendPackageFail failed) sending #{message.id} to #{message.token}/
  end

  test "push reconnects after configured amount of pushes", %{state: state, message: message} do
    state = MessageHandler.push(message, state, FakeSender)
    state = MessageHandler.push(message, state, FakeSender)
    state = MessageHandler.push(message, state, FakeSender)
    output = capture_log(fn -> MessageHandler.push(message, state, FakeSender) end)
    assert output =~ ~s([APNS] 3 messages sent, reconnecting)
    assert output =~ ~s(APNS.FakeSender.close/)
    assert output =~ ~s(APNS.FakeSender.connect_socket)
  end

  test "push counts number of pushes", %{state: state, message: message} do
    state = MessageHandler.push(message, state, FakeSender)
    state = MessageHandler.push(message, state, FakeSender)
    assert state.counter == 2
  end

  test "handle_response calls error callback if status byte is 0" do
    output = capture_log(fn -> MessageHandler.handle_response(response_state(0), "socket", "") end)
    assert output =~ ~s([APNS] Error "No errors encountered" for message 1234)
  end

  test "handle_response calls error callback if status byte is 1" do
    output = capture_log(fn -> MessageHandler.handle_response(response_state(1), "socket", "") end)
    assert output =~ ~s([APNS] Error "Processing error" for message 1234)
  end

  test "handle_response calls error callback if status byte is 2" do
    output = capture_log(fn -> MessageHandler.handle_response(response_state(2), "socket", "") end)
    assert output =~ ~s([APNS] Error "Missing device token" for message 1234)
  end

  test "handle_response calls error callback if status byte is 3" do
    output = capture_log(fn -> MessageHandler.handle_response(response_state(3), "socket", "") end)
    assert output =~ ~s([APNS] Error "Missing topic" for message 1234)
  end

  test "handle_response calls error callback if status byte is 4" do
    output = capture_log(fn -> MessageHandler.handle_response(response_state(4), "socket", "") end)
    assert output =~ ~s([APNS] Error "Missing payload" for message 1234)
  end

  test "handle_response calls error callback if status byte is 5" do
    output = capture_log(fn -> MessageHandler.handle_response(response_state(5), "socket", "") end)
    assert output =~ ~s([APNS] Error "Invalid token size" for message 1234)
  end

  test "handle_response calls error callback if status byte is 6" do
    output = capture_log(fn -> MessageHandler.handle_response(response_state(6), "socket", "") end)
    assert output =~ ~s([APNS] Error "Invalid topic size" for message 1234)
  end

  test "handle_response calls error callback if status byte is 7" do
    output = capture_log(fn -> MessageHandler.handle_response(response_state(7), "socket", "") end)
    assert output =~ ~s([APNS] Error "Invalid payload size" for message 1234)
  end

  test "handle_response calls error callback if status byte is 8" do
    output = capture_log(fn -> MessageHandler.handle_response(response_state(8), "socket", "") end)
    assert output =~ ~s([APNS] Error "Invalid token" for message 1234)
  end

  test "handle_response calls error callback if status byte is 10" do
    output = capture_log(fn -> MessageHandler.handle_response(response_state(10), "socket", "") end)
    assert output =~ ~s([APNS] Error "Shutdown" for message 1234)
  end

  test "handle_response calls error callback if status byte is 255" do
    output = capture_log(fn -> MessageHandler.handle_response(response_state(255), "socket", "") end)
    assert output =~ ~s/[APNS] Error "None (unknown)" for message 1234/
  end

  test "handle_response retries messages later in queue" do
    message1 = %APNS.Message{id: 1}
    message2 = %APNS.Message{id: 1234}
    message3 = %APNS.Message{id: 3}
    message4 = %APNS.Message{id: 4}
    queue = [message4, message3, message2, message1]

    assert %{queue: []} = MessageHandler.handle_response(response_state(8, queue), "socket", "", self())

    refute_receive {_, %APNS.Message{id: 1}}
    refute_receive {_, %APNS.Message{id: 1234}}
    assert_receive {_, %APNS.Message{id: 3}}
    assert_receive {_, %APNS.Message{id: 4}}
  end

  test "handle_response returns state if rest is blank" do
    input_state = response_state(8)
    state = MessageHandler.handle_response(input_state, "socket", "", self())

    assert state == input_state
  end

  test "handle_response iterates over packages until rest is blank" do
    state = response_state(6)
    package1 = apple_buffer(8)
    package2 = apple_buffer(7)
    data = <<package1 :: binary, package2 :: binary>>
    output = capture_log(fn -> MessageHandler.handle_response(state, "socket", data) end)

    assert output =~ ~s([APNS] Error "Invalid topic size" for message 1234)
    assert output =~ ~s([APNS] Error "Invalid token" for message 1234)
    assert output =~ ~s([APNS] Error "Invalid payload size" for message 1234)
  end

  @tag :pending # should we support this case?
  test "handle_response iteration works with error response after success", %{apple_success_buffer: apple_success_buffer} do
    state = %{buffer_apple: apple_success_buffer, config: %{callback_module: APNS.Callback}, queue: []}
    package1 = apple_buffer(8)
    package2 = apple_buffer(7)
    data = <<package1 :: binary, package2 :: binary>>
    output = capture_log(fn -> MessageHandler.handle_response(state, "socket", data) end)

    assert output =~ ~s([APNS] Error "Invalid token" for message 1234)
    assert output =~ ~s([APNS] Error "Invalid payload size" for message 1234)
  end

  @tag :pending # should we support this case?
  test "handle_response iteration works with success response after error", %{apple_success_buffer: apple_success_buffer} do
    state = response_state(6)
    package1 = apple_buffer(8)
    package2 = apple_success_buffer
    package3 = apple_buffer(7)
    data = <<package1 :: binary, package2 :: binary, package3 :: binary>>
    output = capture_log(fn -> MessageHandler.handle_response(state, "socket", data) end)

    assert output =~ ~s([APNS] Error "Invalid topic size" for message 1234)
    assert output =~ ~s([APNS] Error "Invalid token" for message 1234)
    assert output =~ ~s([APNS] Error "Invalid payload size" for message 1234)
  end

  defp response_state(status_code, queue \\ []) do
    %{
      buffer_apple: apple_buffer(status_code),
      config: %{callback_module: APNS.Callback},
      queue: queue
    }
  end

  defp apple_buffer(status_code) do
    <<8 :: 8, status_code :: 8, 1234 :: integer-32>>
  end
end