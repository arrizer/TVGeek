var App, Async, CLIColor, Config, File, FileSystem, HTTP, LibXML, Log, Path, SizeFormatter, TheTVDBAPI, app, log, sortable, sprintf,
  __slice = [].slice;

FileSystem = require('fs');

Path = require('path');

CLIColor = require('cli-color');

sprintf = require('sprintf').sprintf;

HTTP = require('http');

LibXML = require('libxmljs');

Async = require('async');

Log = (function() {
  var DEFAULT, LEVELS;

  LEVELS = {
    debug: {
      level: 0,
      colors: ['blue'],
      textColors: ['blackBright']
    },
    info: {
      level: 1,
      colors: ['cyan'],
      textColors: []
    },
    warn: {
      level: 2,
      colors: ['black', 'bgYellow'],
      textColors: ['yellow']
    },
    error: {
      level: 3,
      colors: ['red'],
      textColors: ['red']
    },
    fatal: {
      level: 4,
      colors: ['white', 'bgRedBright'],
      textColors: ['red']
    }
  };

  DEFAULT = null;

  Log.Default = function() {
    if (DEFAULT == null) {
      DEFAULT = this.Stderr();
    }
    return DEFAULT;
  };

  Log.Stderr = function() {
    return new Log(process.stderr);
  };

  function Log(stream) {
    var level, _fn;
    this.stream = stream;
    this.colored = true;
    this.timestamp = false;
    this.level = 5;
    this.prefix = '';
    _fn = (function(_this) {
      return function(level) {
        return _this[level] = function() {
          var message, parameters;
          message = arguments[0], parameters = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
          return _this.log.apply(_this, [level, message].concat(__slice.call(parameters)));
        };
      };
    })(this);
    for (level in LEVELS) {
      _fn(level);
    }
  }

  Log.prototype.colorize = function() {
    var chain, color, colors, string, _i, _len;
    string = arguments[0], colors = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
    if (!this.colored || (colors == null) || colors.length === 0) {
      return string;
    }
    chain = CLIColor;
    for (_i = 0, _len = colors.length; _i < _len; _i++) {
      color = colors[_i];
      chain = chain[color];
    }
    return chain(string);
  };

  Log.prototype.log = function() {
    var level, line, message, parameters;
    level = arguments[0], message = arguments[1], parameters = 3 <= arguments.length ? __slice.call(arguments, 2) : [];
    line = '';
    if (this.timestamp) {
      line += this.colorize('[' + new Date() + '] ', 'blackBright');
    }
    line += this.colorize.apply(this, ['[' + level.toUpperCase() + ']'].concat(__slice.call(LEVELS[level].colors)));
    line += ' ' + this.colorize.apply(this, [sprintf.apply(null, [this.prefix + message].concat(__slice.call(parameters)))].concat(__slice.call(LEVELS[level].textColors)));
    return this.stream.write(line + "\n", 'utf8');
  };

  return Log;

})();

log = Log.Default();

Config = (function() {
  var DEFAULTS;

  DEFAULTS = {
    inbox: null,
    library: null,
    structure: '%show_sortable%/Season %season%/%show% S%season_00%E%episode_00% %title%',
    policy: 'replaceWhenBigger',
    considerExtensions: ["mp4", "mkv", "avi", "mov"],
    deleteExtensions: []
  };

  function Config(file) {
    this.file = file;
  }

  Config.prototype.read = function(next) {
    return FileSystem.readFile(this.file, (function(_this) {
      return function(error, data) {
        if (error != null) {
          return next(error);
        } else {
          _this.load(JSON.parse(data.toString()));
          return next();
        }
      };
    })(this));
  };

  Config.prototype.load = function(config) {
    var key;
    this.config = DEFAULTS;
    for (key in config) {
      if (key in DEFAULTS) {
        this.config[key] = config[key];
      } else {
        log.warn('Unknown option "%s" in configuration file', key);
      }
    }
    return this.config.considerExtensions = this.config.considerExtensions.map(function(extension) {
      return '.' + extension;
    });
  };

  Config.prototype.get = function() {
    return this.config;
  };

  return Config;

})();

TheTVDBAPI = (function() {
  var API_KEY, BASE;

  function TheTVDBAPI() {}

  API_KEY = '5EFCC7790F190138';

  BASE = 'http://thetvdb.com';

  TheTVDBAPI.prototype.request = function(url, next) {
    var req;
    log.debug('<TVDB> GET %s', url);
    req = HTTP.request(url, (function(_this) {
      return function(res) {
        var body;
        if (res.statusCode === 200) {
          body = '';
          res.on('data', function(data) {
            return body += data.toString();
          });
          return res.on('end', function() {
            return next(null, body);
          });
        } else {
          return next(new Error("tvdb API request to " + url + " failed with HTTP error " + res.statusCode));
        }
      };
    })(this));
    req.on('error', (function(_this) {
      return function(error) {
        return next(error);
      };
    })(this));
    return req.end();
  };

  TheTVDBAPI.prototype.requestXML = function(url, next) {
    return this.request(url, (function(_this) {
      return function(error, data) {
        var xml;
        if (error != null) {
          return next(error);
        } else {
          xml = LibXML.parseXmlString(data);
          return next(null, xml);
        }
      };
    })(this));
  };

  TheTVDBAPI.prototype.show = function(name, next) {
    return this.requestXML(("" + BASE + "/api/GetSeries.php?seriesname=") + encodeURIComponent(name), (function(_this) {
      return function(error, xml) {
        var get, node, shows, _i, _len, _ref;
        if (error != null) {
          return next(error);
        } else {
          shows = [];
          _ref = xml.find('/Data/Series');
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            node = _ref[_i];
            get = function(path) {
              var subnode;
              subnode = node.get(path);
              if (subnode != null) {
                return subnode.text();
              } else {
                return null;
              }
            };
            shows.push({
              id: get('seriesid'),
              language: get('language'),
              name: get('SeriesName'),
              since: get('FirstAired')
            });
          }
          return next(null, shows);
        }
      };
    })(this));
  };

  TheTVDBAPI.prototype.episodeByAirdate = function(showID, airdate, next) {
    airdate = sprintf('%04f-%02f-%02f', airdate.getFullYear(), airdate.getMonth() + 1, airdate.getDate());
    return this.episodeByURL("" + BASE + "/api/GetEpisodeByAirDate.php?apikey=" + API_KEY + "&seriesid=" + showID + "&airdate=" + airdate, next);
  };

  TheTVDBAPI.prototype.episodeBySeasonAndEpisode = function(showID, season, episode, next) {
    return this.episodeByURL("" + BASE + "/api/" + API_KEY + "/series/" + showID + "/default/" + season + "/" + episode + "/en.xml", next);
  };

  TheTVDBAPI.prototype.episodeByURL = function(url, next) {
    return this.requestXML(url, (function(_this) {
      return function(error, xml) {
        var episode, get;
        if (error != null) {
          return next(error);
        } else {
          get = function(key) {
            var node;
            node = xml.get('/Data/Episode/' + key);
            if (node != null) {
              return node.text();
            } else {
              return null;
            }
          };
          episode = {
            id: get('id'),
            airdate: get('FirstAired'),
            title: get('EpisodeName'),
            season: get('SeasonNumber'),
            episode: get('EpisodeNumber'),
            director: get('Director')
          };
          return next(null, episode);
        }
      };
    })(this));
  };

  return TheTVDBAPI;

})();

SizeFormatter = (function() {
  var UNITS;

  function SizeFormatter() {}

  UNITS = ['bytes', 'KiB', 'MiB', 'GiB', 'PiB'];

  SizeFormatter.Format = function(bytes) {
    var factor, unit;
    factor = 1;
    unit = 0;
    while ((factor * 1024) < bytes) {
      factor *= 1024;
      unit++;
    }
    return (Math.round((bytes / factor) * 100) / 100) + ' ' + UNITS[unit];
  };

  return SizeFormatter;

})();

sortable = function(string) {
  var prefix, regexp, _i, _len, _ref;
  _ref = ['The', 'Der', 'Die', 'Das', 'Le', 'Les', 'La', 'Los'];
  for (_i = 0, _len = _ref.length; _i < _len; _i++) {
    prefix = _ref[_i];
    regexp = new RegExp('^' + prefix + ' ', 'i');
    if (regexp.test(string)) {
      return string.replace(regexp, '') + ', ' + prefix;
    }
  }
  return string;
};

File = (function() {
  var AIRDATE_RE, DELIMITERS, SEASON_EPISODE_RE, TVDB;

  SEASON_EPISODE_RE = [/^(.*) s(\d+)e(\d+)/gi, /^(.*?) (\d{1})(\d{2})[^\d]/gi, /^(.*?) (\d{1,2})x(\d{1,2})/gi];

  AIRDATE_RE = [/^(.*) (\d{4}) (\d{2}) (\d{2})/gi];

  TVDB = new TheTVDBAPI();

  DELIMITERS = /[\s,\.\-\+]+/g;

  function File(directory, filename) {
    this.directory = directory;
    this.filename = filename;
    this.extension = Path.extname(this.filename);
    this.name = Path.basename(this.filename, this.extension);
    this.filepath = Path.join(this.directory, this.filename);
    this.fileinfo = FileSystem.statSync(this.filepath);
  }

  File.prototype.match = function(next) {
    log.info('Matching "%s"', this.filename);
    this.nameNormalized = this.name.replace(DELIMITERS, ' ');
    return Async.series([this.extract.bind(this), this.fetchShow.bind(this), this.fetchEpisode.bind(this)], (function(_this) {
      return function(error) {
        if (error != null) {
          log.error("Could not match '%s': %s", _this.filename, error);
        }
        return next(error);
      };
    })(this));
  };

  File.prototype.extract = function(next) {
    var method, _i, _len, _ref;
    _ref = ['extractSeasonAndEpisode', 'extractAirdate'];
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      method = _ref[_i];
      if (this[method]()) {
        return next();
      }
    }
    return next(new Error("Could not extract season/episode or airdate from '" + this.nameNormalized + "'"));
  };

  File.prototype.extractSeasonAndEpisode = function() {
    var match, regexp, _i, _len;
    log.debug('Extracting season/episode from "%s"', this.nameNormalized);
    for (_i = 0, _len = SEASON_EPISODE_RE.length; _i < _len; _i++) {
      regexp = SEASON_EPISODE_RE[_i];
      match = regexp.exec(this.nameNormalized);
      if (match != null) {
        this.extracted = {
          fetch: 'fetchEpisodeBySeasonAndEpisode',
          show: match[1],
          season: parseInt(match[2]),
          episode: parseInt(match[3])
        };
        log.debug('Extracted -> "%s" S%02fE%02f', this.extracted.shpw, this.extracted.season, this.extracted.episode);
        regexp.lastIndex = 0;
        return true;
      }
    }
    return false;
  };

  File.prototype.extractAirdate = function(next) {
    var match, regexp, _i, _len;
    log.debug('Extracting airdate from "%s"', this.nameNormalized);
    for (_i = 0, _len = AIRDATE_RE.length; _i < _len; _i++) {
      regexp = AIRDATE_RE[_i];
      match = regexp.exec(this.nameNormalized);
      if (match != null) {
        this.extracted = {
          fetch: 'fetchEpisodeByAirdate',
          show: match[1],
          airdate: new Date(match[2], parseInt(match[3]) - 1, match[4])
        };
        log.debug('Extracted -> "%s" airdate %s', this.extracted.show, this.extracted.airdate);
        regexp.lastIndex = 0;
        return true;
      }
    }
    return false;
  };

  File.prototype.fetchShow = function(next) {
    return TVDB.show(this.extracted.show, (function(_this) {
      return function(error, shows) {
        if (error != null) {
          return next(new Error("Failed to get show information: " + error));
        } else {
          if (shows.length === 1) {
            return next(null, _this.show = shows[0]);
          } else if (shows.length === 0) {
            return next(new Error("Show named '" + name + "' not found"));
          } else {
            return next(new Error("Show name '" + name + "' is ambigious"));
          }
        }
      };
    })(this));
  };

  File.prototype.fetchEpisode = function(next) {
    return this[this.extracted.fetch]((function(_this) {
      return function(error, episode) {
        if (error != null) {
          return next(new Error("Failed to get episode information: " + error));
        } else {
          return next(null, _this.episode = episode);
        }
      };
    })(this));
  };

  File.prototype.fetchEpisodeBySeasonAndEpisode = function(next) {
    return TVDB.episodeBySeasonAndEpisode(this.show.id, this.extracted.season, this.extracted.episode, next);
  };

  File.prototype.fetchEpisodeByAirdate = function(next) {
    return TVDB.episodeByAirdate(this.show.id, this.extracted.airdate, next);
  };

  File.prototype.libraryPath = function(pattern) {
    var escapeRegExp, key, path, placeholders, value;
    path = pattern;
    placeholders = {
      show: this.show.name,
      season: this.episode.season,
      episode: this.episode.episode,
      title: this.episode.title
    };
    for (key in placeholders) {
      value = placeholders[key];
      value = value.toString().replace(/(\/|\\|:|;)/g, '');
      placeholders[key] = value;
      placeholders[key + '_sortable'] = sortable(value);
      if (/^\d+$/.test(value)) {
        placeholders[key + '_00'] = sprintf('%02f', parseInt(value));
      }
    }
    escapeRegExp = function(string) {
      return string.replace(/([.*+?^=!:${}()|\[\]\/\\])/g, "\\$1");
    };
    for (key in placeholders) {
      value = placeholders[key];
      path = path.replace(new RegExp(escapeRegExp('%' + key + '%'), 'g'), value);
    }
    return path;
  };

  File.prototype.move = function(libraryDir, pattern, overwritePolicy, next) {
    var basename, directory, path;
    path = this.libraryPath(pattern);
    basename = Path.basename(path);
    directory = Path.join(libraryDir, Path.dirname(path));
    return this.makeLibraryPath(libraryDir, directory, (function(_this) {
      return function(error, existed) {
        if (error != null) {
          return next(error);
        } else {
          return _this.overwrite(directory, basename, overwritePolicy, function(fileExisted, move) {
            if (move) {
              return _this.moveTo(libraryDir, path, next);
            } else {
              return next(null, true);
            }
          });
        }
      };
    })(this));
  };

  File.prototype.overwrite = function(directory, basename, overwritePolicy, next) {
    return FileSystem.readdir(directory, (function(_this) {
      return function(error, files) {
        var file, filename, overwrite, stat, _i, _len;
        for (_i = 0, _len = files.length; _i < _len; _i++) {
          file = files[_i];
          if (Path.basename(file, Path.extname(file)) === basename) {
            filename = Path.join(directory, file);
            stat = FileSystem.statSync(filename);
            overwrite = false;
            if (overwritePolicy === 'replaceWhenBigger') {
              if (stat.size < _this.stat.size) {
                log.warn("Smaller file '%s' in library will be replaced", file);
                overwrite = true;
              } else if (stat.size > _this.stat.size) {
                log.warn("Bigger file '%s' (%s > %s) already in library", file, SizeFormatter.Format(stat.size), SizeFormatter.Format(_this.stat.size));
              } else {
                log.warn("File '%s' already in library", file);
              }
            } else if (overwritePolicy === 'always') {
              log.warn("File '%s' in library will be replaced", file);
              overwrite = true;
            }
            if (overwrite) {
              FileSystem.unlink(filename, function(error) {
                log.error("Failed to remove existing file '%s' in library: %s", filename, error);
                return next(true, error == null);
              });
            } else {
              return next(true, false);
            }
          }
        }
        return next(false, true);
      };
    })(this));
  };

  File.prototype.moveTo = function(library, path, next) {
    var destination, origin;
    origin = Path.join(this.directory, this.filename);
    destination = Path.join(library, path + this.extension);
    return FileSystem.rename(origin, destination, next);
  };

  File.prototype.makeLibraryPath = function(library, directory, next) {
    return FileSystem.exists(library, (function(_this) {
      return function(exists) {
        if (!exists) {
          return next(new Error("Library path " + library + " does not exist"));
        }
        return FileSystem.stat(directory, function(error, stat) {
          if ((error != null) && error.name === 'ENOENT') {
            log.debug("Creting subdirectory '%s' in library", directory);
            return FileSystem.mkdir(directory, function(error) {
              return next(error, false);
            });
          } else if (error != null) {
            return next(error);
          } else {
            if (stat.isDirectory()) {
              return next(null, true);
            } else {
              return next(new Error("Path " + directory + " exists but is not a directory"));
            }
          }
        });
      };
    })(this));
  };

  File.prototype.toString = function() {
    return sprintf('%s S%02fE%02f "%s" (%s)', this.show.name, parseInt(this.episode.season), parseInt(this.episode.episode), this.episode.title, SizeFormatter.Format(this.fileinfo.size));
  };

  return File;

})();

App = (function() {
  function App() {}

  App.prototype.main = function() {
    this.config = new Config(__dirname + '/config.json');
    return this.config.read((function(_this) {
      return function() {
        _this.config = _this.config.get();
        return _this.processFiles(_this.config.inbox);
      };
    })(this));
  };

  App.prototype.processFiles = function(inbox) {
    return FileSystem.readdir(inbox, (function(_this) {
      return function(error, files) {
        var extension, file, _i, _len, _results;
        if (error != null) {
          return log.error('Failed to enumerate files in inbox "%s": %s', inbox, error);
        } else {
          _results = [];
          for (_i = 0, _len = files.length; _i < _len; _i++) {
            file = files[_i];
            if (_this.config.considerExtensions.indexOf(Path.extname(file)) >= 0) {
              _results.push(_this.processFile(inbox, file));
            } else {
              _results.push((function() {
                var _j, _len1, _ref, _results1;
                _ref = this.config.deleteExtensions;
                _results1 = [];
                for (_j = 0, _len1 = _ref.length; _j < _len1; _j++) {
                  extension = _ref[_j];
                  if (Path.extname(file) === '.' + extension) {
                    log.info("Deleting file '%s' from inbox", file);
                    _results1.push(FileSystem.unlink(Path.join(inbox, file)));
                  } else {
                    _results1.push(void 0);
                  }
                }
                return _results1;
              }).call(_this));
            }
          }
          return _results;
        }
      };
    })(this));
  };

  App.prototype.processFile = function(inbox, file) {
    var item;
    item = new File(inbox, file);
    return item.match((function(_this) {
      return function(error) {
        if (error == null) {
          log.info('-> %s', item.toString());
          return item.move(_this.config.library, _this.config.structure, _this.config.policy, function(error) {
            if (error != null) {
              return log.error("Failed to move '%s' to library: %s", item.filename, error);
            }
          });
        }
      };
    })(this));
  };

  return App;

})();

app = new App();

app.main();
