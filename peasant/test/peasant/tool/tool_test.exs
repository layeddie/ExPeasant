defmodule Peasant.ToolTest do
  use Peasant.GeneralCase

  alias Peasant.Tools.FakeTool

  defmodule FakeHandler do
    def register(tool), do: send(self(), {:register, tool})
    def attach(tool_uuid), do: send(self(), {:attach, tool_uuid})
  end

  setup_all do
    tool_handler = Application.get_env(:peasant, :tool_handler)
    Application.put_env(:peasant, :tool_handler, FakeHandler)

    on_exit(fn ->
      Application.put_env(:peasant, :tool_handler, tool_handler)
    end)
  end

  setup do
    tool_spec = new_tool()

    assert %FakeTool{} = tool = FakeTool.new(tool_spec)

    [tool_spec: tool_spec, tool: tool]
  end

  describe "Tool module" do
    @describetag :unit

    test "should intoduce State struct and functions", do: :ok
  end

  describe "Registration and register/1" do
    @describetag :unit

    test "should exist" do
      assert {:register, 1} in FakeTool.__info__(:functions)
    end

    test "should return {:ok, uuid} in case of correct tool specs", %{tool_spec: tool_spec} do
      assert {:ok, uuid} = FakeTool.register(tool_spec)
      assert is_binary(uuid)
      assert {:ok, _} = UUID.info(uuid)

      assert_receive {:register, %FakeTool{uuid: ^uuid}}
    end

    test "should return {:error, error} in case of incorrect tool specs" do
      tool = new_tool() |> Map.delete(:name)
      assert {:error, _} = FakeTool.register(tool)

      refute_receive {:register, %FakeTool{}}
    end

    test "should introduce __Tool__.Registered event struct", %{tool: tool} do
      assert Code.ensure_compiled(FakeTool.Registered)
      assert %FakeTool.Registered{tool: ^tool} = FakeTool.Registered.new(tool)
    end
  end

  describe "attach(tool_uuid)" do
    @describetag :unit

    test "should run Handler.attach(tool_uuid)", %{tool: %{uuid: uuid}} do
      assert :ok = FakeTool.attach(uuid)

      assert_receive {:attach, ^uuid}
    end
  end
end
