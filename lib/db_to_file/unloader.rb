module DbToFile
  class Unloader
    def initialize
      # Load config and build database connection, before stashing possible changes
      @config ||= load_config
      ActiveRecord::Base.connection.select('show tables')
    end

    def unload
      prepare_code_version
      unload_tables
      update_code_version
      restore_local_stash
    end

    private
      def prepare_code_version
        version_controller.prepare_code_version
      end

      def unload_tables
        puts 'Start downloading tables'
        tables.each do |table|
          puts "Downloading table #{table}"
          unload_table(table)
        end
        puts 'Done downloading tables'
      end

      def update_code_version
        puts 'Start updating code version'
        version_controller.update_code_version
        puts 'Done updating code version'
      end

      def restore_local_stash
        version_controller.restore_local_stash
      end

      def version_controller
        @version_controller ||= VersionController.new
      end

      def tables
        config['tables'].keys
      end

      def config_directory_prefix(table)
        config['tables'][table]['directory_prefix'] if config['tables'][table].present?
      end

      def config_field_extension(table, field)
        begin
          config['tables'][table]['field_extensions'][field]
        rescue NoMethodError
          nil
        end
      end

      def config_ignore_columns(table)
        config['tables'][table]['ignore_columns'] if config['tables'][table].present?
      end

      def unload_table(table)
        table.singularize.classify.constantize.all.each do |record|
          build_directory_for_record(record)
          build_files_for_record_fields(record, config_ignore_columns(table))
        end
      end

      def build_directory_for_record(record)
        FileUtils.mkdir_p(directory_for_record(record))
      end

      def build_files_for_record_fields(record, ignore_columns)
        base_dir = directory_for_record(record)
        normalized_hash = DbToFile::ValuesNormalizer::ObjectToHash.new(record).normalize
        normalized_hash.except(*ignore_columns).each_pair do |field, value|
          file_name = file_with_extension(table(record), field)
          full_file_path = File.join(base_dir, file_name)
          handle = File.open(full_file_path, 'w')
          handle.write(value)
          handle.close
        end
      end

      def file_with_extension(table, field)
        if (extension = config_field_extension(table, field)).present?
          "#{field}.#{extension}"
        else
          field
        end
      end

      def directory_for_record(record)
        "db/db_to_file/#{table(record)}/#{row_name(record)}"
      end

      def table(record)
        record.class.table_name
      end

      def row_name(record)
        [directory_prefix(record), record.id.to_s].compact.reject(&:empty?).join('_')
      end

      def directory_prefix(record)
        table = record.class.table_name
        "#{(record.send(config_directory_prefix(table)) || '').parameterize}" if config_directory_prefix(table).present?
      end

      def config
        @config ||= load_config
      end

      def load_config
        YAML::load(File.read(config_file))
      end

      def config_file
        'config/db_to_file.yml'
      end
  end
end
