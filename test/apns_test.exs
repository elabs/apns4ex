defmodule APNSTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  require Logger

  # @moduletag :capture_log

  @our_phone_token "8a61a279e0a35396d08ce13131fa6e2278a404f53683f17f16e6d6666223c712"
  @our_other_phone_token "4e9ecf4b1aa1e79bf1f654d31d9c775d9afa2e803dc416a78818585bb76df089"

  setup do
    message =
      APNS.Message.new(23)
      |> Map.put(:token, "1becf2320bcd26819f96d2d75d58b5e81b11243286bc8e21f54c374aa44a9155")
      |> Map.put(:alert, "Lorem ipsum dolor sit amet, consectetur adipisicing elit")

    {:ok, %{message: message}}
  end

  test "APNS starts all the pools from config" do
    for {pool, _conf} <- Application.get_env(:apns, :pools) do
      assert {:ready, _, _, _} = :poolboy.status(String.to_atom("APNS.Pool.#{to_string(pool)}"))
    end
  end

  @tag :real
  test "push/2 pushes message to worker", %{message: message} do
    output = capture_log(fn -> assert :ok = APNS.push(:test, message) end)
    assert output =~ ~s([APNS] success sending 23 to 1becf2320bcd26819f96d2d75d58b5e81b11243286bc8e21f54c374aa44a9155)
  end

  @tag :real
  test "push_parallel/2 works with many invalid tokens" do
    # output = capture_log(fn ->

  Logger.info "========================================================="

  # :observer.start()
    # for _i <- (1..30) do
    #   push_parallel()
    # end
    #
    # push_parallel("60d66b38d8b6d471e8283d1d10d1fd00c540f7e1415c46480c6243e7b19d55c0")
    #
    for _i <- (1..30) do
      push_parallel()
    end

    # push_parallel("bffbe11169889c4aec135bb986fac7fe5a20bb56f116d263be91bf1c1db60bad")
    push_parallel("bffbe11169889c4aec135bb986fac7fe5a20bb56f116d263be91bf1c1db60e30")
    # push_parallel(@our_phone_token)
    push_parallel(@our_other_phone_token)
    push_parallel("46b4c7fdfa1dd4e8e7e4054bc8f05150fac06583ed128a29ca0aef770eb8758b")

    for _i <- (1..30) do
      push_parallel()
    end

    push_parallel("686327addad787c39f32d04d2a003dc6a02c1981ec5a6f29f5453ff144321f35")
    for _i <- (1..30) do
      push_parallel()
    end
    # push_parallel(@our_other_phone_token)
    push_parallel(@our_phone_token)
    for _i <- (1..30) do
      push_parallel()
    end

    Logger.info("Sleeping…")
    :timer.sleep(50000)
    # end)
    # assert output =~ ~s([APNS] success sending 23 to 1becf2320bcd26819f96d2d75d58b5e81b11243286bc8e21f54c374aa44a9155)
  end

  @tag :real
  test "push_parallel/2 send one parallel to good token" do
    for _i <- (1..30) do
      push_parallel()
    end
    push_parallel("bffbe11169889c4aec135bb986fac7fe5a20bb56f116d263be91bf1c1db60e30")

    push_parallel(@our_phone_token)
    :timer.sleep 50000
  end

  @tag :real
  test "push_parallel/2 don't tuch me I will allways work" do
    push_parallel(@our_other_phone_token)
    :timer.sleep 3000
  end

  # generates genserver timeout and ssl close with 2 workers and 0 overflow
  # @tag :real
  # test "push/2 works with many invalid tokens" do
    #   Logger.info "========================================================="
  #
  #   :observer.start()
  #     for _i <- (1..1000) do
  #       send_random()
  #       #:timer.sleep 100
  #       Logger.info "-----------------------------"
  #     end
  #     :timer.sleep(30000)
  # end

  defp push_parallel do
    push_parallel(Base.encode16(:crypto.strong_rand_bytes(32), case: :lower))
  end

  defp push_parallel(token) do
    notification = %{
      body_loc_key: "START_UNTITLED_BROADCAST_FORMAT",
      body_loc_args: ["broadcaster name"],
      body: "broadcaster name just started broadcasting.",
      title: "broadcaster name is live!",
      title_loc_key: "USER_LIVE_FORMAT",
      title_loc_args: ["broadcaster name"]
    }

    message =
      APNS.Message.new()
      |> Map.put(:alert, notification)
      |> Map.put(:category, "broadcast_started")
      |> Map.put(:extra, %{video_id: 123})
      |> Map.put(:support_old_ios, false)
      |> Map.put(:token, token)

    # message =
    #   APNS.Message.new()
    #   |> Map.put(:token, token)
    #   |> Map.put(:alert, "Lorem ipsum dolor sit amet, consectetur adipisicing elit")

    :ok = APNS.push_parallel(:test, message)
    Logger.info "-----------------------------"
  end
end
