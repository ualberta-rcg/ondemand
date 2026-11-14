module ActiveJobs
  # Model for view data from PBS-Ruby response.
  #
  # The PBS-Ruby results are much larger than this app needs them to be
  # so this model extracts the necessary info to send to the user.
  #
  # @author Brian L. McMichael
  # @version 0.0.1
  class Jobstatusdata
    attr_reader :pbsid, :jobname, :username, :account, :status, :cluster, :cluster_title, :nodes, :starttime, :walltime, :walltime_used, :submit_args, :output_path, :nodect, :ppn, :total_cpu, :queue, :cput, :mem, :gpus, :vmem, :shell_url, :file_explorer_url, :extended_available, :native_attribs, :error

    Attribute = Struct.new(:name, :value)

    # Define an object containing only necessary data to send to client.
    #
    # Object defaults to condensed data, add extended flag to initializer to include all data used by the application.
    #
    # @param [OodCore::Job::Info] info An OodCore.job_adapter.info[_all] response object
    # @param [OodCore::Cluster, #to_sym] cluster The string name of a cluster configured in the OODClusters list (ex. 'oakley')
    # @param [Boolean, nil] extended If true, included extended data in the response (default: false)
    # @return [Jobstatusdata] self
    def initialize(info, cluster=OODClusters.first, extended=false)
      cluster = OODClusters[cluster]
      raise ArgumentError, "Invalid cluster" unless cluster

      self.pbsid = info.id
      self.jobname = info.job_name
      self.username = info.job_owner
      self.account = info.accounting_id || ''
      self.status = info.status.state.to_s
      self.cluster = cluster.id.to_s
      self.cluster_title = cluster.title
      self.walltime_used = info.wallclock_time.to_i > 0 ? pretty_time(info.wallclock_time) : ''
      self.queue = info.queue_name
      self.gpus = info.gpus
      if info.status == :running || info.status == :completed
        self.nodes = node_array(info.allocated_nodes).reject(&:blank?)
        self.starttime = info.dispatch_time.to_i
      end
      self.extended_available = %w(torque slurm lsf pbspro).include?(cluster.job_config[:adapter])
      if extended
        if cluster.job_config[:adapter] == "torque"
          extended_data_torque(info)
        elsif cluster.job_config[:adapter] == "slurm"
          extended_data_slurm(info)
        elsif cluster.job_config[:adapter] == "lsf"
          extended_data_lsf(info)
        elsif cluster.job_config[:adapter] == "pbspro"
          extended_data_pbspro(info)
        elsif cluster.job_config[:adapter] == "sge"
          extended_data_sge(info)
        elsif cluster.job_config[:adapter] == "fujitsu_tcs"
          extended_data_fujitsu_tcs(info)
        else
          extended_data_default(info)
        end
      end
      self
    end

    # Store additional data about the job. (Torque-specific)
    #
    # Parses the `native` info function for additional information about jobs on Torque systems.
    #   https://github.com/OSC/ood_core/blob/master/spec/job/adapters/torque_spec.rb
    #
    # @return [Jobstatusdata] self
    def extended_data_torque(info)
      return unless info.native
      attributes = []
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.cluster'), self.cluster_title
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.pbs_id'), self.pbsid
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.job_name'), self.jobname
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.user'), self.username
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.account'), self.account
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.submission_time'), safe_parse_time(info.submission_time) if info.submission_time
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.walltime'), (info.wallclock_limit ? pretty_time(info.wallclock_limit) : "00:00:00")
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.walltime_used'), self.walltime_used
      node_count = info.native.fetch(:Resource_List, {})[:nodect].to_i
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.node_count'), node_count
      ppn = info.native.fetch(:Resource_List, {})[:nodes].to_s.split("ppn=").second || '0'
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.node_list'), self.nodes.join(", ") unless self.nodes.blank?
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.ppn'), ppn
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.total_cpus'), ppn.to_i * node_count.to_i
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.cpu_time'), info.native.fetch(:resources_used, {})[:cput].presence || '0'
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.memory'), info.native.fetch(:resources_used, {})[:mem].presence || "0 b"
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.virtual_memory'), info.native.fetch(:resources_used, {})[:vmem].presence || "0 b"
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.comment'), info.native[:comment] if info.native[:comment]
      self.native_attribs = attributes

      self.submit_args = info.native[:submit_args].presence || I18n.t('dashboard.active_jobs_detail.none')
      self.output_path = info.native[:Output_Path].to_s.split(":").second || info.native[:Output_Path]

      output_pathname = Pathname.new(self.output_path).dirname
      self.file_explorer_url = build_file_explorer_url(output_pathname)
      self.shell_url = build_shell_url(output_pathname, self.cluster)

      self
    end

    # Store additional data about the job. (SLURM-specific)
    #
    # Parses the `native` info function for additional information about jobs on SLURM systems.
    #   https://github.com/OSC/ood_core/blob/master/spec/job/adapters/slurm_spec.rb
    #
    # @return [Jobstatusdata] self
    def extended_data_slurm(info)
      return unless info.native
      attributes = []
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.cluster'), self.cluster_title
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.job_id'), self.pbsid
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.array_job_id'), info.native[:array_job_id]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.array_task_id'), info.native[:array_task_id]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.job_name'), self.jobname
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.user'), self.username
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.account'), self.account
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.partition'), self.queue
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.state'), info.native[:state]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.reason'), info.native[:reason]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.total_nodes'), info.native[:nodes]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.node_list'), self.nodes.join(", ") unless self.nodes.blank?
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.total_cpus'), info.native[:cpus]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.time_limit'), (info.wallclock_limit ? pretty_time(info.wallclock_limit) : "00:00:00")
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.time_used'), self.walltime_used
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.submission_time'), safe_parse_time(info.submission_time) if info.submission_time
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.start_time'), safe_parse_time(info.native[:start_time])
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.end_time'), safe_parse_time(info.native[:end_time])
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.memory'), info.native[:min_memory]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.gres'), info.native[:gres].gsub(/gres:/, "") unless ['', 'N/A'].include?(info.native[:gres].to_s)
      self.native_attribs = attributes

      self.submit_args = nil
      self.output_path = info.native[:work_dir]

      output_pathname = Pathname.new(info.native[:work_dir])
      self.file_explorer_url = build_file_explorer_url(output_pathname)
      self.shell_url = build_shell_url(output_pathname, self.cluster)

      self
    end

    # Store additional data about the job. (LSF-specific)
    #
    # Parses the `native` info function for additional information about jobs on LSF systems.
    #   https://github.com/OSC/ood_core/blob/master/spec/job/adapters/lsf_spec.rb
    #
    # @return [Jobstatusdata] self
    def extended_data_lsf(info)
      return unless info.native
      attributes = []
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.job_id'), self.pbsid
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.user'), self.username
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.queue'), self.queue
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.cluster'), self.cluster_title
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.from_host'), info.native[:from_host]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.exec_host'), info.native[:exec_host]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.job_name'), self.jobname
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.submission_time'), safe_parse_time(info.submission_time) if info.submission_time
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.project_name'), info.native[:project]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.walltime'), (info.wallclock_limit ? pretty_time(info.wallclock_limit) : "00:00:00")
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.cpu_used'), info.native[:cpu_used]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.mem'), info.native[:mem]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.swap'), info.native[:swap]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.pids'), info.native[:pids]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.node_list'), self.nodes.join(", ") unless self.nodes.blank?
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.start_time'), info.native[:start_time]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.finish_time'), info.native[:finish_time]

      self.native_attribs = attributes

      # LSF output is a little sparse at the moment. No output path or submit args are available.

      self
    end

    # Store additional data about the job. (PBSPro-specific)
    #
    # Parses the `native` info function for additional information about jobs on PBSPRO systems.
    #
    # @return [Jobstatusdata] self
    def extended_data_pbspro(info)
      return unless info.native

      attributes = []
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.cluster'), self.cluster_title
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.pbs_id'), self.pbsid
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.job_name'), self.jobname
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.user'), self.username
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.account'), self.account if info.accounting_id
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.submission_time'), safe_parse_time(info.submission_time) if info.submission_time
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.group_list'), info.native[:group_list] if info.native[:group_list]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.walltime'), (info.wallclock_limit ? pretty_time(info.wallclock_limit) : "00:00:00")
      walltime_used = info.wallclock_time || 0
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.walltime_used'), self.walltime_used
      node_count = info.native.fetch(:Resource_List, {})[:nodect].to_i
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.node_count'), node_count.to_s
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.node_list'), self.nodes.join(", ") unless self.nodes.blank?
      total_procs = info.native[:Resource_List][:ncpus].presence || '0'
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.total_cpus'), total_procs
      cput = info.native.fetch(:resources_used, {})[:cput].presence || 0
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.cpu_time'), pretty_time(cput.to_i)
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.memory'), info.native.fetch(:resources_used, {})[:mem].presence || "0 b"
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.virtual_memory'), info.native.fetch(:resources_used, {})[:vmem].presence || "0 b"
      select = info.native.fetch(:Resource_List, {})[:select].presence
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.select'), select if select
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.comment'), info.native[:comment] || ''
      self.native_attribs = attributes
      self.submit_args = info.native[:Submit_arguments].presence || I18n.t('dashboard.active_jobs_detail.none')
      self.output_path = info.native[:Output_Path].to_s.split(":").second || info.native[:Output_Path]

      output_pathname = Pathname.new(self.output_path).dirname
      self.file_explorer_url = build_file_explorer_url(output_pathname)
      self.shell_url = build_shell_url(output_pathname, self.cluster)

      self
    end

    # Store additional data about the job. (SGE-specific)
    #
    # Parses the `native` info function for additional information about jobs on SGE systems.
    #
    # @return [Jobstatusdata] self
    def extended_data_sge(info)
      return unless info.native
      attributes = []
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.cluster'), self.cluster_title
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.cluster_id'), self.cluster
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.job_id'), self.pbsid
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.job_name'), self.jobname
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.user'), self.username
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.account'), self.account
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.queue'), self.queue
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.start_time'), self.starttime
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.walltime_used'), self.walltime_used
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.status'), self.status

      {
        I18n.t('dashboard.active_jobs_detail.job_version') => :JB_version,
        I18n.t('dashboard.active_jobs_detail.job_exec_file') => :JB_exec_file,
        I18n.t('dashboard.active_jobs_detail.job_script_file') => :JB_script_file,
        I18n.t('dashboard.active_jobs_detail.job_script_size') => :JB_script_size,
        I18n.t('dashboard.active_jobs_detail.job_execution_time') => :JB_execution_time,
        I18n.t('dashboard.active_jobs_detail.job_deadline') => :JB_deadline,
        I18n.t('dashboard.active_jobs_detail.job_uid') => :JB_uid,
        I18n.t('dashboard.active_jobs_detail.job_group') => :JB_group,
        I18n.t('dashboard.active_jobs_detail.job_gid') => :JB_gid,
        I18n.t('dashboard.active_jobs_detail.job_account') => :JB_account,
        I18n.t('dashboard.active_jobs_detail.current_working_directory') => :JB_cwd,
        I18n.t('dashboard.active_jobs_detail.notifications') => :JB_notify,
        I18n.t('dashboard.active_jobs_detail.job_type') => :JB_type,
        I18n.t('dashboard.active_jobs_detail.reserve') => :JB_reserve,
        I18n.t('dashboard.active_jobs_detail.job_priority') => :JB_priority,
        I18n.t('dashboard.active_jobs_detail.job_share') => :JB_jobshare,
        I18n.t('dashboard.active_jobs_detail.job_verify') => :JB_verify,
        I18n.t('dashboard.active_jobs_detail.job_checkpoint_attr') => :JB_checkpoint_attr,
        I18n.t('dashboard.active_jobs_detail.job_checkpoint_interval') => :JB_checkpoint_interval,
        I18n.t('dashboard.active_jobs_detail.job_restart') => :JB_restart
      }.each do |k,v|
        attributes.push Attribute.new k, info.native[v] if info.native[v]
      end

      self.native_attribs = attributes

      self.submit_args = info.native[:ST_name]
      self.output_path = info.native[:PN_path]

      if self.output_path
        output_pathname = Pathname.new(self.output_path).dirname
        self.file_explorer_url = build_file_explorer_url(output_pathname)
        self.shell_url = build_shell_url(output_pathname, self.cluster)
      end

      self
    end

    # Store additional data about the job. (Fujitsu TCS specific)
    #
    # @return [Jobstatusdata] self
    def extended_data_fujitsu_tcs(info)
      return unless info.native
      attributes = []
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.nodes'), info.native[:NODES]
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.time_limit'), pretty_time(info.wallclock_limit)
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.submission_time'), safe_parse_time(info.submission_time) if info.submission_time
      attributes.push Attribute.new I18n.t('dashboard.active_jobs_detail.start_time'), info.native[:START_DATE]
      self.native_attribs = attributes

      output_pathname = Pathname.new(info.native[:STD]).dirname
      self.file_explorer_url = build_file_explorer_url(output_pathname)
      self.shell_url = build_shell_url(output_pathname, self.cluster)

      self
    end

    # This should not be called, but it is available as a template for building new native parsers.
    def extended_data_default(info)
      return unless info.native

      self.native_attribs = []

      self.submit_args = ''
      self.output_path = ''

      output_pathname = Pathname.new(ENV["HOME"])
      self.file_explorer_url = build_file_explorer_url(output_pathname)
      self.shell_url = build_shell_url(output_pathname, self.cluster)

      self
    end

    private

      # Format a time in the server's local timezone, including the zone name.
      # Strings with a UTC offset (e.g. Slurm with SLURM_TIME_FORMAT) are
      # converted, strings without one are assumed to already be local time.
      # Anything else that does not respond to #to_time is blank.
      def safe_parse_time(time)
        return '' if time.blank? || ['N/A', 'NONE'].include?(time.to_s)

        time = if time.is_a?(String)
                 Time.parse(time)
               elsif time.respond_to?(:to_time)
                 time.to_time
               else
                 return ''
               end
        time.getlocal.strftime('%Y-%m-%d %H:%M:%S %Z')
      rescue ArgumentError
        ''
      end

      def build_file_explorer_url(path)
        writable_path = (path.writable? ? path : ENV["HOME"]).to_s

        return OodAppkit.files.url(path: writable_path).to_s
      end

      def build_shell_url(path, cluster)
        writable_path = (path.writable? ? path : ENV["HOME"]).to_s
        host = OODClusters[cluster].login.host if OODClusters[cluster] && OODClusters[cluster].login_allow?

        return OodAppkit.shell.url(path: writable_path, host: host).to_s
      end

      # Rails default string formatters only support HH:MM:SS and roll over the days, so we need to create our own.
      #
      # @param [Integer] The time in seconds
      # @return [String] The time as string formatted as "DDd HH:MM"
      def pretty_time(seconds)
        duration=Array.new
        units=[ [":", 60*60], [":", 60], ["", 1] ]
        units.each do |value|
          unit = seconds.divmod(value[1])
          duration.push("#{"%02d" % unit[0]}#{value[0]}")
          seconds = unit[1]
        end

        return duration.join('')
      end

      # Converts the `allocated_nodes` object array into an array of node names
      #
      # @example [#<OodCore::Job::NodeInfo:0x00000009d3ff78 @name="n0544", @procs=2>] => ['n0544']
      #
      # @param [Array<OodCore::Job::NodeInfo>]
      # @return [Array<String>] the nodes as array
      def node_array(node_info_array)
        node_info_array.map { |n| n.name }
      end

      attr_writer :pbsid, :jobname, :username, :account, :status, :cluster, :cluster_title, :nodes, :starttime, :walltime, :walltime_used, :submit_args, :output_path, :nodect, :ppn, :total_cpu, :queue, :gpus, :cput, :mem, :vmem, :shell_url, :file_explorer_url, :extended_available, :native_attribs, :error

  end
end
