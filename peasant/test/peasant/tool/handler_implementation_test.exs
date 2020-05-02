defmodule Peasant.Tool.HandlerImplementationTest do
  use Peasant.GeneralCase

  import Peasant.Collection.TestHelper

  alias Peasant.Repo

  alias Peasant.Tool.Handler

  alias Peasant.Tools.FakeTool
  alias Peasant.Tool.Action

  @tools Peasant.Tool.domain()

  setup do
    Peasant.subscribe(@tools)
    # GenServer.stop(Peasant.Collection.Observer.Tools)
  end

  setup context do
    [tool: make_tool(context)]
  end

  describe "persist" do
    @describetag :unit

    setup :register_tool_setup

    test "should persist current state and continue with the given next action",
         %{tool: tool} do
      assert {:noreply, stored_tool, {:continue, :registered}} =
               Handler.handle_continue({:persist, :registered}, tool)

      assert tool == stored_tool |> nilify_timestamps()

      assert stored_tool == Repo.get(tool.uuid, @tools)
      assert stored_tool == Peasant.Collection.Keeper.get_by_id(tool.uuid)
    end

    test "should persist current state and stop if no next_action or it is nil",
         %{tool: tool} do
      assert {:noreply, stored_tool} = Handler.handle_continue(:persist, tool)

      assert tool == stored_tool |> nilify_timestamps()

      assert stored_tool == Repo.get(tool.uuid, @tools)
      assert stored_tool == Peasant.Collection.Keeper.get_by_id(tool.uuid)
    end
  end

  describe "registration process" do
    @describetag :unit

    setup :register_tool_setup

    test "init(%{new: true} = tool) should return {:ok, %{tool | new: false}, {:continue, {:persist, :registered}}}",
         %{tool: tool} do
      assert {:ok, %{tool | new: false}, {:continue, {:persist, :registered}}} ==
               Handler.init(tool)
    end

    test "should notify about tool registeration", %{
      tool_registered: %{details: %{tool: tool}} = registered
    } do
      assert {:noreply, %{tool | new: false}} == Handler.handle_continue(:registered, tool)
      assert_receive ^registered
    end
  end

  describe "load process" do
    @describetag :unit

    setup :load_tool_setup

    test "init(%{new: false} = tool) should return {:ok, tool, {:continue, :loaded}}", %{
      tool: tool
    } do
      assert {:ok, tool, {:continue, :loaded}} == Handler.init(%{tool | new: false})
    end

    test "should notify about tool loading", %{tool_loaded: loaded, tool: tool} do
      assert {:noreply, tool} == Handler.handle_continue(:loaded, tool)
      assert_receive ^loaded
    end
  end

  # describe "deletion process" do
  #   @describetag :unit

  #   setup :register_tool_setup

  #   test "should return {:reply, {:error, :tool_should_be_detached}, tool} if tool is attached",
  #        %{tool: tool} do
  #     assert {:ok, {:error, :tool_should_be_detached}, tool} == Handler.handle_call(:delete, tool)
  #   end

  #   test "should notify about tool deletion", %{
  #     tool_registered: %{details: %{tool: tool}} = registered
  #   } do
  #     assert {:noreply, %{tool | new: false}} == Handler.handle_continue(:registered, tool)
  #     assert_receive ^registered
  #   end
  # end

  describe "commit action process" do
    @describetag :unit

    setup :commit_action_setup

    test "should return {:error, :not_attached} if a tool isn't attached",
         %{tool: tool} do
      action = Action.FakeAction
      action_config = %{}

      assert {:reply, {:error, :not_attached}, tool} =
               Handler.handle_call({:commit, action, action_config}, self(), tool)

      refute_receive _, 10
    end

    defmodule FakeTool2 do
      use Peasant.Tool.State
    end

    test "should return {:error, :action_not_supported} if action isn't implemented for the given tool" do
      tool = new_tool() |> FakeTool2.new() |> Map.put(:attached, true)
      action = Action.FakeAction
      action_config = %{}

      error = {:error, Keyword.put([], FakeTool2, :action_not_supported)}

      assert {:reply, ^error, ^tool} =
               Handler.handle_call({:commit, action, action_config}, self(), tool)
    end

    test "for the Attach action should return {:ok, action_ref} and {:continue, {:commit, action, action_config, action_ref}} for not attached tools",
         %{tool: tool} do
      action = Action.Attach
      action_config = %{}

      assert {:reply, {:ok, action_ref}, ^tool,
              {:continue, {:commit, ^action, ^action_config, action_ref}}} =
               Handler.handle_call({:commit, action, action_config}, self(), tool)

      refute_receive _, 10
    end

    test "should return {:ok, action_ref} and {:continue, {:commit, action, action_config, action_ref}}",
         %{tool: tool} do
      tool = %{tool | attached: true}

      action = Action.FakeAction
      action_config = %{}

      assert {:reply, {:ok, action_ref}, ^tool,
              {:continue, {:commit, ^action, ^action_config, action_ref}}} =
               Handler.handle_call({:commit, action, action_config}, self(), tool)

      refute_receive _, 10
    end

    test "should fire returned from action implementation events and put a new tool structure into the state",
         %{tool: tool} do
      action = Action.FakeAction
      action_config = %{}
      action_ref = UUID.uuid4()

      assert {:ok, new_tool, [event]} = Action.FakeAction.run(tool, action_ref)

      assert {:noreply, new_tool} ==
               Handler.handle_continue({:commit, action, action_config, action_ref}, tool)

      assert_receive ^event
    end

    test "should fire returned from action implementation events and put a new tool structure into the state 2",
         %{tool: %{config: config} = tool} do
      action = Action.FakeAction
      action_config = %{}
      action_ref = UUID.uuid4()

      error = Faker.Lorem.sentence()
      config = Map.put(config, :error, error)

      tool = %{tool | config: config, attached: true}

      assert {:ok, ^tool, [event]} = Action.FakeAction.run(tool, action_ref)

      assert {:noreply, tool} ==
               Handler.handle_continue({:commit, action, action_config, action_ref}, tool)

      assert_receive ^event
    end
  end

  def make_tool(%{tool_error: error}) do
    %{config: %{pid: self(), error: error}}
    |> new_tool()
    |> FakeTool.new()
  end

  def make_tool(_) do
    %{config: %{pid: self()}}
    |> new_tool()
    |> FakeTool.new()
  end

  def register_tool_setup(%{tool: tool}) do
    registered =
      Peasant.Tool.Event.Registered.new(
        tool_uuid: tool.uuid,
        details: %{tool: %{tool | new: false}}
      )

    [tool_registered: registered]
  end

  def load_tool_setup(%{tool: tool}) do
    tool = %{tool | new: false}

    loaded = Peasant.Tool.Event.Loaded.new(tool_uuid: tool.uuid, details: %{tool: tool})

    [tool_loaded: loaded, tool: tool]
  end

  def commit_action_setup(%{tool: %{config: config} = tool}) do
    to_change = Faker.Lorem.word()
    config = Map.put(config, :to_change, to_change)
    tool = %{tool | config: config}
    [tool: tool]
  end
end
