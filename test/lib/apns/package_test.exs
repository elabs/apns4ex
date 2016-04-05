defmodule APNS.PackageTest do
  use ExUnit.Case

  @payload_min_size 38

  setup do
    message =
      %APNS.Message{}
      |> Map.put(:token, String.duplicate("0", 64))
      |> Map.put(:alert, String.duplicate("lorem ipsum", 100))
      |> Map.put(:token, "1becf2320bcd26819f96d2d75d58b5e81b11243286bc8e21f54c374aa44a9155")
      |> Map.put(:id, 123)
      |> Map.put(:expiry, 45)

    {:ok, %{message: message}}
  end

  test "to_binary converts json string to binary", %{message: message} do
    now = :os.system_time(:seconds)
    payload = APNS.Payload.build_json(message, 256)
    expected_expiry = now + 45

    assert <<
      2 :: 8,
      312 :: 32,
      frame :: binary
    >> = APNS.Package.to_binary(message, payload, now)

    assert <<
      1 :: 8,
      32 :: 16,
      token_bin :: 32-binary,
      2 :: 8,
      256 :: 16,
      alert :: 256-binary,
      3 :: 8,
      4 :: 16,
      123 :: 32,
      4 :: 8,
      4 :: 16,
      expiry :: 32,
      5 :: 8,
      1 :: 16,
      10 :: 8
    >> = frame

    assert Base.encode16(token_bin) == "1BECF2320BCD26819F96D2D75D58B5E81B11243286BC8E21F54C374AA44A9155"
    assert Poison.decode!(alert)["aps"]["alert"] =~ "lorem ipsumlorem"
    assert expiry == expected_expiry
  end
end
