defmodule BunkerTest do
  use ExUnit.Case, async: false

  alias Bunker

  setup do
    original_enabled = Application.get_env(:bunker, :enabled)
    original_repos = Application.get_env(:bunker, :repos)

    on_exit(fn ->
      Application.put_env(:bunker, :enabled, original_enabled)
      Application.put_env(:bunker, :repos, original_repos)
    end)

    :ok
  end

  describe "configuration" do
    test "enabled?/0 returns configuration" do
      Application.put_env(:bunker, :enabled, true)
      assert Bunker.enabled?() == true

      Application.put_env(:bunker, :enabled, false)
      assert Bunker.enabled?() == false
    end

    test "repos/0 returns configuration" do
      Application.put_env(:bunker, :repos, [MyApp.Repo])
      assert Bunker.repos() == [MyApp.Repo]
    end

    test "adapters/0 returns configuration" do
      adapters = Bunker.adapters()
      assert is_list(adapters)
      assert Bunker.Adapters.GRPC in adapters
    end
  end

  describe "disabled/1" do
    test "temporarily disables isolation checks" do
      result =
        Bunker.disabled(fn ->
          assert Bunker.in_transaction?() == false
          :ok
        end)

      assert result == :ok
    end

    test "re-enables after function completes" do
      Bunker.disabled(fn -> :ok end)
      # Should be enabled again (though in_transaction? depends on actual transaction state)
      assert Process.get(:bunker_disabled) == nil
    end
  end
end
