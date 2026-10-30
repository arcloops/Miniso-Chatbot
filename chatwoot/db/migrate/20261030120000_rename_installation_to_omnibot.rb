class RenameInstallationToOmnibot < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:installation_configs)

    %w[INSTALLATION_NAME BRAND_NAME].each do |name|
      config = InstallationConfig.find_by(name: name)
      next if config.blank?

      config.update!(value: 'OmniBot')
    end
  end

  def down
    return unless table_exists?(:installation_configs)

    %w[INSTALLATION_NAME BRAND_NAME].each do |name|
      config = InstallationConfig.find_by(name: name)
      next if config.blank? || config.value != 'OmniBot'

      config.update!(value: 'Chatwoot')
    end
  end
end
