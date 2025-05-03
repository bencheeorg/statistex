defmodule Statistex.Helper do
  @moduledoc false
  # Everyone loves helper modules... ok ok, no. But I needed/wanted this function,
  # but didn't wanna put it on the main module.

  # With the design goal that we don't want to needlessly do operations, esp. big ones
  # like sorting we need an optional `sorted?` arguments in a bunch of places.
  # This unifies the handling of that.
  def maybe_sort(samples, options) do
    sorted? = Access.get(options, :sorted?, false)

    if sorted? do
      samples
    else
      Enum.sort(samples)
    end
  end
end
