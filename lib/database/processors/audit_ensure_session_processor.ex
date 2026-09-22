# This code has been auto-generated
# Changes to this file will be lost on next generation

defmodule Database.Processors.AuditEnsureSessionProcessor do
  @moduledoc """
  Processor for parsing results from audit.ensure_session
  """

  alias Database.Models.AuditEnsureSessionModel

  @doc """
  Parse the result of the database query into a list of AuditEnsureSessionModel structs
  """
  @spec parse_result({:ok, %Postgrex.Result{}} | {:error, any()}) :: {:ok, [%AuditEnsureSessionModel{}]} | {:error, any()}
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
  Parse a single result row into a AuditEnsureSessionModel struct
  """
  @spec parse_result_row(list()) :: {:ok, %AuditEnsureSessionModel{}} | {:error, any()}
  def parse_result_row([ensure_session]) do
    {:ok, %AuditEnsureSessionModel{
      ensure_session: ensure_session
    }}
  end

  def parse_result_row(row) do
    {:error, "Unexpected row format: #{inspect(row)}"}
  end
end
