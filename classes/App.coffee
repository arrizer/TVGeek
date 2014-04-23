#_require Log
#_require Config
#_require File
#_require SizeFormatter

class App
  main: ->
    @config = new Config(__dirname + '/config.json')
    @config.read =>
      @config = @config.get()
      @processFiles @config.inbox

  processFiles: (inbox) ->
    FileSystem.readdir inbox, (error ,files) =>
      if error?
        log.error 'Failed to enumerate files in inbox "%s": %s', inbox, error
      else
        for file in files
          if @config.considerExtensions.indexOf(Path.extname(file)) >= 0
            @processFile inbox, file
          else
            for extension in @config.deleteExtensions
              if Path.extname(file) is '.' + extension
                log.info "Deleting file '%s' from inbox", file
                FileSystem.unlink Path.join(inbox, file)

  processFile: (inbox, file) ->
    item = new File(inbox, file)
    item.match (error) =>
      unless error?
        log.info '-> %s', item.toString()
        item.move @config.library, @config.structure, @config.policy, (error) =>
          log.error "Failed to move '%s' to library: %s", item.filename, error if error?