defmodule Peasant.Automation.HandlerBasicAutomationProcess do
  use Peasant.GeneralCase

  alias Peasant.Automation.State
  alias Peasant.Automation.Handler
  alias Peasant.Automation.Event

  @automations Peasant.Automation.domain()

  setup do
    Peasant.subscribe(@automations)
    :ok
  end

  setup :automation_setup

  describe "handle_continue(:next_step, automation)" do
    @describetag :unit

    test "should stop if automation deactivated",
         %{automation: automation} do
      automation = %{automation | active: false}

      assert {:noreply, automation} ==
               Handler.handle_continue(:next_step, automation)

      refute_receive _, 10
    end

    test "if current last_step_index + 1 == total_steps should return {:continue, :next_step}, set :last_step_index to -1",
         %{automation: %{total_steps: total_steps} = automation} do
      assert {
               :noreply,
               %{automation | last_step_index: -1},
               {:continue, :next_step}
             } ==
               Handler.handle_continue(:next_step, %{
                 automation
                 | last_step_index: total_steps - 1
               })

      refute_receive _, 10
    end

    test "should return {:continue, {:cache_till_reboot, {:maybe_start_step, current_step}}}",
         %{
           automation:
             %{
               steps: steps,
               last_step_index: last_step_index
             } = automation
         } do
      current_step_index = last_step_index + 1
      current_step = Enum.at(steps, current_step_index)

      assert {
               :noreply,
               %State{},
               {:continue, {:cache_till_reboot, {:maybe_start_step, ^current_step}}}
             } = Handler.handle_continue(:next_step, automation)
    end

    test "should set :last_step_index and :last_step_attempted_at",
         %{
           automation:
             %{
               last_step_index: last_step_index
             } = automation
         } do
      current_step_index = last_step_index + 1
      last_step_attempted_at = now()

      assert {
               :noreply,
               %State{
                 last_step_attempted_at: ts,
                 last_step_index: ^current_step_index
               },
               _
             } = Handler.handle_continue(:next_step, automation)

      assert_in_delta last_step_attempted_at, ts, 20

      refute_receive _, 10
    end
  end

  describe "handle_continue({:maybe_start_step, current_step}, automation)" do
    @describetag :unit

    test "if step is inactive should return {:noreply, automation, {:continue, {:step_skipped, current_step}}}",
         %{
           automation:
             %{
               steps: [current_step | _]
             } = automation
         } do
      current_step = %{current_step | active: false}

      assert {:noreply, automation, {:continue, {:step_skipped, current_step}}} ==
               Handler.handle_continue(
                 {:maybe_start_step, current_step},
                 automation
               )
    end

    test "if step is active should return {:noreply, automation, {:continue, {:step_started, current_step}}}",
         %{
           automation:
             %{
               steps: [current_step | _]
             } = automation
         } do
      assert {:noreply, automation, {:continue, {:step_started, current_step}}} ==
               Handler.handle_continue(
                 {:maybe_start_step, current_step},
                 automation
               )
    end
  end

  describe "handle_continue({:step_skipped, current_step}, automation)" do
    @describetag :integration

    # setup %{automation: %{uuid: uuid}} do
    #   start_supervised(Peasant.Automation.FakeHandler.start_link(%{uuid: uuid, test_pid: self()}))

    #   :ok
    # end

    test "should return {:noreply, automation}, fire StepSkipped event and call :next_step", %{
      automation:
        %{
          uuid: automation_uuid,
          steps: [%{uuid: step_uuid} = current_step | _]
        } = automation
    } do
      last_step_attempted_at = now()
      last_step_index = Faker.random_between(0, 10)

      automation = %{
        automation
        | last_step_index: last_step_index,
          last_step_attempted_at: last_step_attempted_at
      }

      assert {:noreply, automation} ==
               Handler.handle_continue({:step_skipped, current_step}, automation)

      assert_receive %Event.StepSkipped{
        automation_uuid: ^automation_uuid,
        step_uuid: ^step_uuid,
        index: ^last_step_index,
        timestamp: ^last_step_attempted_at
      }

      assert_receive :next_step
    end
  end

  describe "handle_continue({:step_started, current_step}, automation)" do
    @describetag :unit

    test "should fire StepStarted event", %{
      automation:
        %{
          uuid: automation_uuid,
          steps: [%{uuid: step_uuid} = current_step | _]
        } = automation
    } do
      last_step_attempted_at = now()
      last_step_index = Faker.random_between(0, 10)

      automation = %{
        automation
        | last_step_index: last_step_index,
          last_step_attempted_at: last_step_attempted_at
      }

      assert {:noreply, _, {:continue, {:do_step, ^current_step}}} =
               Handler.handle_continue({:step_started, current_step}, automation)

      assert_receive %Event.StepStarted{
        automation_uuid: ^automation_uuid,
        step_uuid: ^step_uuid,
        index: ^last_step_index,
        timestamp: ^last_step_attempted_at
      }
    end
  end

  describe "handle_info(:next_step, automation)" do
    @describetag :unit

    test "should return {:noreply, automation, {:continue, :next_step}}", %{
      automation: automation
    } do
      assert {:noreply, automation, {:continue, :next_step}} ==
               Handler.handle_info(:next_step, automation)
    end
  end

  describe "handle_continue({:do_step, current_step}, automation)" do
    @describetag :unit

    test "should NOT return {:noreply, automation} if automation went inactive",
         %{
           automation:
             %{
               steps: [current_step | _]
             } = automation
         } do
      refute {:noreply, %{automation | active: false}} ==
               Handler.handle_continue({:do_step, current_step}, %{automation | active: false})
    end

    test "should generate a random reference value, start a timer and return timer reference and reference value in automation",
         %{automation: automation} do
      time_to_wait = 50

      %{uuid: step_uuid} =
        current_step = new_step_struct(type: "awaiting", time_to_wait: time_to_wait, active: true)

      assert {:noreply, %State{timer: timer, timer_ref: ^step_uuid}} =
               Handler.handle_continue({:do_step, current_step}, automation)

      assert is_reference(timer)
      time_left = Process.read_timer(timer)
      assert is_integer(time_left)
      assert time_left > 0
      assert time_left <= time_to_wait

      assert_receive {:waiting_finished, ^step_uuid}, time_to_wait + 50
    end
  end

  describe "handle_continue({:fail_step, current_step, error}, automation)" do
    @describetag :unit

    test "should cast :next_step and fire StepFailed event",
         %{
           automation:
             %{
               uuid: automation_uuid,
               steps: [%{uuid: step_uuid} | _],
               last_step_index: last_step_index
             } = automation
         } do
      now = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      last_step_attempted_at = now - 1_000
      current_step_index = last_step_index + 1
      error = [error: "something"]

      assert {:noreply, _} =
               Handler.handle_continue({:fail_step, step_uuid, error}, %{
                 automation
                 | last_step_index: current_step_index,
                   last_step_attempted_at: last_step_attempted_at
               })

      assert_receive %Event.StepFailed{
        automation_uuid: ^automation_uuid,
        step_uuid: ^step_uuid,
        index: ^current_step_index,
        timestamp: step_finished_timestamp,
        step_duration: step_duration,
        details: ^error
      }

      assert_in_delta now, step_finished_timestamp, 20
      assert_in_delta now - last_step_attempted_at, step_duration, 20

      assert_receive :next_step
    end
  end

  describe "handle_continue({:finish_step, step_uuid}, automation)" do
    @describetag :unit

    test "should fire StepStopped event and cast :next_step",
         %{
           automation:
             %{
               uuid: automation_uuid,
               steps: [%{uuid: current_step_uuid} | _],
               last_step_index: last_step_index
             } = automation
         } do
      now = now()
      last_step_attempted_at = now - 1_000
      current_step_index = last_step_index + 1

      assert {:noreply, _} =
               Handler.handle_continue({:finish_step, current_step_uuid}, %{
                 automation
                 | last_step_index: current_step_index,
                   last_step_attempted_at: last_step_attempted_at
               })

      assert_receive %Event.StepStopped{
        automation_uuid: ^automation_uuid,
        step_uuid: ^current_step_uuid,
        index: ^current_step_index,
        timestamp: step_finished_timestamp,
        step_duration: step_duration
      }

      assert_in_delta now, step_finished_timestamp, 20
      assert_in_delta now - last_step_attempted_at, step_duration, 20

      assert_receive :next_step
    end
  end

  describe "handle_info({:waiting_finished, timer_ref}, automation)" do
    @describetag :unit

    test "should return {:noreply, automation, {:continue, {:finish_step, step}} and nilify timer and timer_ref if timer ref equals to current step uuid",
         %{
           automation:
             %{
               steps:
                 [
                   %{uuid: current_step_uuid} | _
                 ] = _steps
             } = automation
         } do
      timer = Process.send_after(self(), :nothing, 1_000)
      timer_ref = current_step_uuid

      automation = %{automation | last_step_index: 0, timer_ref: timer_ref, timer: timer}

      assert {:noreply, %{automation | timer: nil, timer_ref: nil},
              {:continue, {:finish_step, current_step_uuid}}} ==
               Handler.handle_info({:waiting_finished, timer_ref}, automation)
    end

    test "should return {:noreply, automation} if timer ref is different",
         %{
           automation:
             %{
               steps:
                 [
                   %{uuid: step_uuid} | _
                 ] = _steps
             } = automation
         } do
      timer_ref1 = UUID.uuid4()
      timer_ref2 = UUID.uuid4()

      automation = %{automation | last_step_index: 0, timer_ref: timer_ref1}

      assert {:noreply, automation} ==
               Handler.handle_info({:waiting_finished, step_uuid, timer_ref2}, automation)
    end

    test "should return {:noreply, automation} if current step uuid is different",
         %{
           automation: automation
         } do
      timer_ref = UUID.uuid4()

      automation = %{automation | last_step_index: 0, timer_ref: timer_ref}

      assert {:noreply, automation} ==
               Handler.handle_info({:waiting_finished, UUID.uuid4(), timer_ref}, automation)
    end
  end

  def automation_setup(_context) do
    automation = new_automation() |> State.new()

    total_steps = 5
    steps = 1..total_steps |> Enum.map(fn _ -> new_step_struct(active: true) end)

    automation = %{
      automation
      | total_steps: total_steps,
        steps: steps,
        last_step_index: -1,
        active: true,
        new: false
    }

    [automation: automation]
  end
end
