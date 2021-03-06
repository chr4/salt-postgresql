# Do not overcommit memory
#
# In Linux 2.4 and later, the default virtual memory behavior is not optimal for PostgreSQL.
# Because of the way that the kernel implements memory overcommit, the kernel might terminate the
# PostgreSQL postmaster (the master server process) if the memory demands of either PostgreSQL or
# another process cause the system to run out of virtual memory.
# If PostgreSQL itself is the cause of the system running out of memory, you can avoid the problem
# by changing your configuration. In some cases, it may help to lower memory-related configuration
# parameters, particularly shared_buffers and work_mem. In other cases, the problem may be caused
# by allowing too many connections to the database server itself. In many cases, it may be better
# to reduce max_connections and instead make use of external connection-pooling software.
#
# See: https://www.postgresql.org/docs/current/kernel-resources.html#LINUX-MEMORY-OVERCOMMIT
vm.overcommit_memory:
  sysctl.present:
    - value: 2

# Default value of 50% for overcommit_ratio might be too low on systems without swap. It should
# be increased on systems where higher virtual memory might need to be allocated
# Virtual memory allocation can be a bit more generous on system with enough RAM available.
# - https://man7.org/linux/man-pages/man5/proc.5.html
vm.overcommit_ratio:
  sysctl.present:
    - value: {{ salt['pillar.get']('sysctl:vm.overcommit_ratio', 50) }}
