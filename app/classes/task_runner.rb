#TaskRunner is the link between the Cloudpatrol webapp and the underlying gem that actually talks to AWS
#Not sure the origin of the term 'task' but this object reminds me of a loader in Java that would
#use reflection... preps the proper argument values from the Setting model object (from the db) and then
#invokes the method of the cloudpatrol facade in the gem
class TaskRunner
  def initialize(command = {})
    @command = {
      class: command[:class].to_sym,
      method: command[:method].to_sym
    }
    @creds = creds
  end

  def run
    if @creds and task_class_has_public_method(@command[:class],@command[:method])
      request_args = prepare_cloudpatrol_arguments(@creds, log_table_name, @command[:class], @command[:method])
      Cloudpatrol.perform(*request_args)
    else
      raise
    end
  rescue
    false
  end

private

  def prepare_cloudpatrol_arguments(creds, log_table_name, task_class_name, method_name)
    request_args = [ creds, log_table_name, task_class_name, method_name ]
    task_arg = fetch_numeric_value

    unless task_arg.nil?
      request_args << task_arg
      request_args << fetch_whitelist
    end
    request_args
  end

  def task_class_has_public_method(task_class_name, method_name)
    Cloudpatrol::Task.const_get(task_class_name).public_instance_methods(false).include?(method_name)
  end


  def fetch_whitelist(whitelist_key_prefix='whitelist')
    found_settings = Setting.where('key LIKE :prefix', prefix: "#{whitelist_key_prefix}%")

    whitelist = []
    found_settings.each do |found_setting|
      unless found_setting.value.blank?
        whitelist << found_setting.value
      end
    end
    whitelist
  end

  def fetch_numeric_value
    setting_key = map_command_class_and_method_to_setting_key(@command[:class], @command[:method])

    if setting_key
      setting_value = retrieve_setting_value(setting_key)
      if setting_value.present?
        setting_value.to_i
      else
        raise "#{setting_key} must exist"
      end
    else
      nil
    end
  end

  def map_command_class_and_method_to_setting_key(class_name, method_name)
    case class_name
      when :EC2
        'ec2_instance_age' if method_name == :clean_instances
      when :OpsWorks
        case method_name
          when :clean_stacks
            'opsworks_stack_age'
          else
            nil
        end
      when :CloudFormation
        'cloudformation_stack_age' if method_name == :clean_stacks
      else
        nil
    end
  end

  def retrieve_setting_value(setting_key)
    Setting.find_by_key(setting_key).try(:value)
  end

  def log_table_name
    retrieve_setting_value('dynamodb_log_table') || 'cloudpatrol-log'
  end

  def creds
    access_key_id = Setting.find_by_key('aws_access_key_id').try(:value)
    secret_access_key = Setting.find_by_key('aws_secret_access_key').try(:value)
    if access_key_id  and secret_access_key
      {
        access_key_id: access_key_id,
        secret_access_key: secret_access_key
      }
    else
      nil
    end
  end
end
