{BufferedProcess, Emitter, CompositeDisposable} = require 'atom'
{spawn} = require 'child_process'
path = require 'path'

module.exports =
class CommandRunner
  constructor: ->
    @running = false
    @subscriptions = new CompositeDisposable()
    @emitter = new Emitter()

  spawnProcess: (command) ->
    @running = true

    shell = atom.config.get('run-command.shellCommand') || '/bin/bash'
    useLogin = atom.config.get('run-command.useLoginShell')

    args = ['-c', command]
    if useLogin
      args = ['-l'].concat(args)

    @process = spawn shell, args, {
      cwd: @constructor.workingDirectory()
      env: process.env
      shell: true
    }

    @process.stdout.on 'data', (data) =>
      @emitter.emit('data', data.toString())
    @process.stderr.on 'data', (data) =>
      @emitter.emit('data', data.toString())
    @process.on 'exit', (code) =>
      @running = false
      @emitter.emit('exit', code)
    @process.on 'close', (code) =>
      @running = false
      @emitter.emit('close', code)

  @homeDirectory: ->
    process.env['HOME'] || process.env['USERPROFILE'] || '/'

  @workingDirectory: ->
    editor = atom.workspace.getActiveTextEditor()
    activePath = editor?.getPath()
    relative = atom.project.relativizePath(activePath)
    if activePath?
      relative[0] || path.dirname(activePath)
    else
      atom.project.getPaths()?[0] || @homeDirectory()

  onCommand: (handler) ->
    @emitter.on 'command', handler
  onData: (handler) ->
    @emitter.on 'data', handler
  onExit: (handler) ->
    @emitter.on 'exit', handler
  onKill: (handler) ->
    @emitter.on 'kill', handler
  onClose: (handler) ->
    @emitter.on 'close', handler

  run: (command) ->
    new Promise (resolve, reject) =>
      @kill()
      @emitter.emit('command', command)

      result =
        output: ''
        exited: false
        signal: null

      @spawnProcess(command)

      @subscriptions.add @onData (data) =>
        result.output += data
      @subscriptions.add @onClose (code) =>
        result.exited = true
        result.exitCode = code
        resolve(result)
      @subscriptions.add @onKill (signal) =>
        result.signal = signal
        resolve(result)

  kill: (signal) ->
    signal ||= 'SIGTERM'

    if @process? && @running
      @emitter.emit('kill', signal)
      @process.kill(signal)
      @process = null

      @subscriptions.dispose()
      @subscriptions.clear()
