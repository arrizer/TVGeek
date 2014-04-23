{exec} = require 'child_process'
Rehab = require 'coffeescript-rehab'
fs = require 'fs'
path = require 'path'
pkg = require './package.json'

task 'build', 'Build coffee script to single nodejs file', ->
  files = Rehab.process(path.join __dirname, 'classes')
  wrapper = '#!/usr/bin/env coffee' + "\n" + fs.readFileSync(path.join __dirname, 'wrapper.coffee').toString()
  code = ''
  for file in files
    code += fs.readFileSync(file).toString() + "\n"
  code = wrapper.replace '{code}', code
  scriptfile = path.join(__dirname, pkg.name + '.coffee')
  fs.writeFileSync(scriptfile, code)
  exec "coffee --no-header --bare --compile #{scriptfile}", (err, stdout, stderr) ->
    if err?
      throw err