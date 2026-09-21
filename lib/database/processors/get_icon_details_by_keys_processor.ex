# This code has been auto-generated
# Changes to this file will be lost on next generation

defmodule Database.Processors.GetIconDetailsByKeysProcessor do
  @moduledoc """
  Processor for parsing results from public.get_icon_details_by_keys
  """

  alias Database.Models.GetIconDetailsByKeysModel

  @doc """
  Parse the result of the database query into a list of GetIconDetailsByKeysModel structs
  """
  @spec parse_result({:ok, %Postgrex.Result{}} | {:error, any()}) :: {:ok, [%GetIconDetailsByKeysModel{}]} | {:error, any()}
  def parse_result({:ok, %Postgrex.Result{rows: rows}}) do
    parsed_results = rows |> Enum.map(&parse_result_row/1)

    errors = parsed_results |> Enum.filter(&(elem(&1, 0) == :error))

    if Enum.empty?(errors) do
      successful_results = parsed_results |> Enum.map(&elem(&1, 1))
      {:ok, successful_results}
    else
      {:error, errors}
    end
  end

  def parse_result({:error, error}), do: {:error, error}

  @doc """
  Parse a single result row into a GetIconDetailsByKeysModel struct
  """
  @spec parse_result_row(list()) :: {:ok, %GetIconDetailsByKeysModel{}} | {:error, any()}
  def parse_result_row([request_index, icon_id, icon_set_code, icon_set_title, name, nrm_name, style_code, sizes, has_single_source, is_scalable, filenames]) do
    {:ok, %GetIconDetailsByKeysModel{
      request_index: request_index,
      icon_id: icon_id,
      icon_set_code: icon_set_code,
      icon_set_title: icon_set_title,
      name: name,
      nrm_name: nrm_name,
      style_code: style_code,
      sizes: sizes,
      has_single_source: has_single_source,
      is_scalable: is_scalable,
      filenames: filenames
    }}
  end

  def parse_result_row(row) do
    {:error, "Unexpected row format: #{inspect(row)}"}
  end
end
