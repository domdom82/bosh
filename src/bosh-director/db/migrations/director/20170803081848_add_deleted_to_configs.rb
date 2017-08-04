Sequel.migration do
  change do
    alter_table(:configs) do
      add_column(:deleted, TrueClass, default: false)
    end
  end
end
