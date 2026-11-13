# frozen_string_literal: true

# Helpers for the system status page /dashboard/systemstatus
module SystemStatusHelper
  def title(cluster)
    I18n.t('dashboard.system_status_cluster_title', title: cluster.title)
  end

  def status_hash(name, active, total)
    {
      message: I18n.t('dashboard.system_status_available', name: name, count: number_with_delimiter(total - active)),
      percent: percent(active, total)
    }
  end

  def not_slurm_hash(job_adapter)
    scheduler = job_adapter.class.name.demodulize
    {
      message: I18n.t('dashboard.system_status_not_slurm', scheduler: scheduler),
      percent: -1
    }
  end

  def components_status(job_adapter)
    begin
      cluster_info = job_adapter.cluster_info
    rescue NotImplementedError
      return [not_slurm_hash(job_adapter)]
    end

    [
      status_hash(I18n.t('dashboard.system_status_nodes'), cluster_info.active_nodes, cluster_info.total_nodes),
      status_hash(I18n.t('dashboard.system_status_processors'), cluster_info.active_processors, cluster_info.total_processors),
      status_hash(I18n.t('dashboard.system_status_gpus'), cluster_info.active_gpus, cluster_info.total_gpus)
    ]
  end

  def percent(value, total)
    "#{(value.to_f / total * 100).round 2}%"
  end

  def valid_percent?(percent)
    percent.to_f >= 0
  end

  def active_jobs(job_adapter)
    job_adapter.info_all_each.select do |info|
      info.status.running?
    end.length
  end

  def active_job_status(job_adapter)
    num_jobs = number_with_delimiter(active_jobs(job_adapter))
    I18n.t('dashboard.system_status_jobs_running_count', count: num_jobs)
  end

  def queued_jobs(job_adapter)
    job_adapter.info_all_each.select do |info|
      info.status.queued?
    end.length
  end

  def queued_job_status(job_adapter)
    num_jobs = number_with_delimiter(queued_jobs(job_adapter))
    I18n.t('dashboard.system_status_jobs_queued_count', count: num_jobs)
  end

  def active_job_pct(job_adapter)
    percent(active_jobs(job_adapter), active_jobs(job_adapter) + queued_jobs(job_adapter))
  end

  def queued_job_pct(job_adapter)
    percent(queued_jobs(job_adapter), active_jobs(job_adapter) + queued_jobs(job_adapter))
  end
end
