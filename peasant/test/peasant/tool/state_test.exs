defmodule Peasant.Tool.StateTest do
  use Peasant.GeneralCase

  defmodule FakeState do
    use Peasant.Tool.State, no_config: true
  end

  @new_state_required_fields [
    :name,
    :config
  ]

  setup do
    state_params = new_tool()

    state = FakeState.new(state_params)

    assert %FakeState{uuid: _} = state

    [state_params: state_params, state: state]
  end

  describe "Tool State" do
    @describetag :unit

    test "should have used Peasant.Schema as a basement", do: :ok

    test "should cast all fields", %{state_params: state_params, state: state} do
      check_recursive(state_params, state)
    end

    test "should return an error if there is no required field", %{state_params: state_params} do
      Enum.each(@new_state_required_fields, fn req_field ->
        assert {:error,
                [
                  {
                    ^req_field,
                    {"can't be blank", [validation: :required]}
                  }
                ]} = state_params |> Map.delete(req_field) |> FakeState.new()
      end)
    end

    test "should have :attached field", %{state: state} do
      assert Map.has_key?(state, :attached)
      assert state.attached == false
    end

    test "should have :new field", %{state: state} do
      assert Map.has_key?(state, :new)
      assert state.new == true
    end

    test "should have timestamps", %{state: state} do
      assert Map.has_key?(state, :inserted_at)
      assert Map.has_key?(state, :updated_at)
    end
  end
end
