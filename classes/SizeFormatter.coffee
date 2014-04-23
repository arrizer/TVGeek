class SizeFormatter
  UNITS = ['bytes','KiB','MiB','GiB','PiB']

  @Format: (bytes) ->
    factor = 1
    unit = 0
    while (factor * 1024) < bytes
      factor *= 1024
      unit++
    return (Math.round((bytes / factor) * 100) / 100) + ' ' + UNITS[unit]