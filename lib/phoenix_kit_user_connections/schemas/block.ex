defmodule PhoenixKitUserConnections.Block do
  @moduledoc """
  Schema for user blocking relationships.
  """
  use Ecto.Schema
  use PhoenixKit.SchemaPrefix
  import Ecto.Changeset

  alias PhoenixKit.Utils.Date, as: UtilsDate

  @primary_key {:uuid, UUIDv7, autogenerate: true}

  @type t :: %__MODULE__{
          uuid: UUIDv7.t() | nil,
          blocker_uuid: UUIDv7.t(),
          blocked_uuid: UUIDv7.t(),
          reason: String.t() | nil,
          blocker: PhoenixKit.Users.Auth.User.t() | Ecto.Association.NotLoaded.t(),
          blocked: PhoenixKit.Users.Auth.User.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil
        }

  schema "phoenix_kit_user_blocks" do
    belongs_to(:blocker, PhoenixKit.Users.Auth.User,
      foreign_key: :blocker_uuid,
      references: :uuid,
      type: UUIDv7
    )

    belongs_to(:blocked, PhoenixKit.Users.Auth.User,
      foreign_key: :blocked_uuid,
      references: :uuid,
      type: UUIDv7
    )

    field(:reason, :string)
    field(:inserted_at, :utc_datetime)
  end

  def changeset(block, attrs) do
    block
    |> cast(attrs, [:blocker_uuid, :blocked_uuid, :reason])
    |> validate_required([:blocker_uuid, :blocked_uuid])
    # 255, not 500: the column is `character varying(255)`. A longer reason
    # passed validation and then raised `Postgrex.Error` on insert, so the
    # caller got a crash where it had asked for a changeset error.
    #
    # `count: :codepoints` matters as much as the number. Ecto counts
    # GRAPHEME CLUSTERS by default; Postgres counts characters. 255 decomposed
    # graphemes ("e" + U+0301, say) are 510 codepoints, which passes a default
    # `max: 255` and is still refused by the column with
    # `:string_data_right_truncation` — the exact crash this validation exists
    # to prevent, just needing an accented reason to reach it.
    |> validate_length(:reason, max: 255, count: :codepoints)
    |> validate_not_self_block()
    |> put_inserted_at()
    |> foreign_key_constraint(:blocker_uuid)
    |> foreign_key_constraint(:blocked_uuid)
    |> unique_constraint([:blocker_uuid, :blocked_uuid],
      name: :phoenix_kit_user_blocks_unique_idx,
      message: "user is already blocked"
    )
  end

  defp validate_not_self_block(changeset) do
    blocker_uuid = get_field(changeset, :blocker_uuid)
    blocked_uuid = get_field(changeset, :blocked_uuid)

    if blocker_uuid && blocked_uuid && blocker_uuid == blocked_uuid do
      add_error(changeset, :blocked_uuid, "cannot block yourself")
    else
      changeset
    end
  end

  defp put_inserted_at(changeset) do
    if get_field(changeset, :inserted_at) do
      changeset
    else
      put_change(changeset, :inserted_at, UtilsDate.utc_now())
    end
  end
end
