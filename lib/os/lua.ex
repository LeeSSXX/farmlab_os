defmodule FarmbotOS.Lua do
  @moduledoc """
  Embedded scripting language for "formulas" in the MOVE block,
  assertion, and general scripting via LUA block.
  """
  require FarmbotOS.Logger
  require Logger

  alias FarmbotOS.Lua.{
    DataManipulation,
    Firmware,
    Info,
    Wait,
    PinWatcher
  }

  # this function is used by SysCalls, but isn't a direct requirement.
  @doc "Logs an assertion based on it's result"
  def log_assertion(passed?, type, message) do
    meta = [assertion_passed: passed?, assertion_type: type]
    FarmbotOS.Logger.dispatch_log(:assertion, 2, message, meta)
  end

  # HACK: Provide an implicit "return", since many users
  #       will want implicit returns. If we didn't do this,
  #       users would be forced to write `return` everywhere,
  #       even in the formula input seen in the MOVE block.
  def add_implicit_return(str) do
    # Don't add implicit return if:
    #   * Contains carraige return ("\n")
    #   * Contains assignment char ("=")
    #   * Contains `return` keyword
    has_return? = String.contains?(str, "return")
    has_assignment? = String.contains?(str, "=")
    has_cr? = String.contains?(str, "\n")
    properly_formed? = has_cr? || has_assignment? || has_return?

    if properly_formed? do
      str
    else
      "return (#{str})"
    end
  end

  @doc """
  `extra_vm_args` is a set of extra args to place inside the
  Lua sandbox. The extra args are passed to set_table/3
  """
  def perform_lua(lua_code, extra_vm_args, _comment) do
    lua_code = add_implicit_return(lua_code)
    reducer = fn args, vm -> apply(__MODULE__, :set_table, [vm | args]) end
    vm = Enum.reduce(extra_vm_args, init(), reducer)
    FarmbotOS.Lua.Result.new(raw_eval(vm, lua_code))
  end

  def init do
    reducer = fn {k, v}, lua -> set_table(lua, [k], v) end
    Enum.reduce(builtins(), :luerl.init(), reducer)
  end

  def wrap(fun, _name) do
    fn args, lua ->
      if FarmbotOS.BotState.fetch().informational_settings.locked do
        :the_device_is_estopped
      else
        # Every FarmBot related function triggers a GC sweep.
        result = fun.(args, :luerl.gc(lua))
        result
      end
    end
  end

  def set_table(lua, [name] = path, fun) when is_function(fun) do
    :luerl.set_table(path, wrap(fun, name), lua)
  end

  def set_table(lua, path, value) do
    :luerl.set_table(path, value, lua)
  end

  def raw_eval(lua, hook) when is_binary(hook) do
    :luerl.eval(hook, lua)
  end

  def execute_script(name) do
    fn _, lua ->
      case FarmbotOS.SysCalls.Farmware.execute_script(name, %{}) do
        {:error, reason} -> {[reason], lua}
        :ok -> {[], lua}
        other -> {[inspect(other)], lua}
      end
    end
  end

  def builtins() do
    %{
      base64: [
        {:decode, &DataManipulation.b64_decode/2},
        {:encode, &DataManipulation.b64_encode/2}
      ],
      json: [
        {:decode, &DataManipulation.json_decode/2},
        {:encode, &DataManipulation.json_encode/2}
      ],
      uart: [
        {:open, &FarmbotOS.Firmware.LuaUART.open/2},
        {:list, &FarmbotOS.Firmware.LuaUART.list/2}
      ],
      auth_token: &Info.auth_token/2,
      check_position: &Firmware.check_position/2,
      coordinate: &Firmware.coordinate/2,
      current_hour: &Info.current_hour/2,
      current_minute: &Info.current_minute/2,
      current_month: &Info.current_month/2,
      current_second: &Info.current_second/2,
      emergency_lock: &Firmware.emergency_lock/2,
      emergency_unlock: &Firmware.emergency_unlock/2,
      soft_stop: &Firmware.soft_stop/2,
      env: &DataManipulation.env/2,
      fbos_version: &Info.fbos_version/2,
      find_axis_length: &Firmware.calibrate/2,
      find_home: &Firmware.find_home/2,
      firmware_version: &Info.firmware_version/2,
      garden_size: &DataManipulation.garden_size/2,
      get_device: &DataManipulation.get_device/2,
      get_fbos_config: &DataManipulation.get_fbos_config/2,
      get_firmware_config: &DataManipulation.get_firmware_config/2,
      get_position: &Firmware.get_position/2,
      go_to_home: &Firmware.go_to_home/2,
      http: &DataManipulation.http/2,
      inspect: &DataManipulation.json_encode/2,
      move_absolute: &Firmware.move_absolute/2,
      new_sensor_reading: &DataManipulation.new_sensor_reading/2,
      photo_grid: &DataManipulation.photo_grid/2,
      read_pin: &Firmware.read_pin/2,
      read_status: &Info.read_status/2,
      send_message: &Info.send_message/2,
      set_pin_io_mode: &Firmware.set_pin_io_mode/2,
      soil_height: &DataManipulation.soil_height/2,
      take_photo_raw: &DataManipulation.take_photo_raw/2,
      take_photo: execute_script("take-photo"),
      calibrate_camera: execute_script("camera-calibration"),
      detect_weeds: execute_script("plant-detection"),
      measure_soil_height: execute_script("Measure Soil Height"),
      update_device: &DataManipulation.update_device/2,
      update_fbos_config: &DataManipulation.update_fbos_config/2,
      update_firmware_config: &DataManipulation.update_firmware_config/2,
      wait: &Wait.wait/2,
      watch_pin: &PinWatcher.new/2,
      write_pin: &Firmware.write_pin/2
    }
  end
end
