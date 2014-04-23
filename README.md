# TVGeek

TVGeek is a small node.js script, that organizes TV show video files from some incoming directory  into a nicely organized folder structure.

## How does it work?

TVGeek will look for files in an inbox directory and tries to extract show title, season, episode, air date and other information out of the filename. The show and episode are then looked up at [The TV DB](http://thetvdb.com). The file is then moved into a nicely organized folder structure based in its metadata.

## Install

To install, simply run `npm install` from the directory to install dependencies.

## Configure

The configuration file is called `config.json` and may contain the following keys:

- `inbox` = The path containing the unorganized TV show video files
- `library` = The root path under which files are organized in a folder structure (must be on the same physical disk as the `inbox`
- `structure` = A relative path below the `library` path containing placeholders (see below for details)
- `policy` = What to do when a file with the same name is already in the library (`always` will always replace the existing file, `replaceWhenBigger` = replace the file in the library when the incoming file is bigger, `never` = Never overwrite anything)
- `considerExtensions` = An array of file extensions that are processed (other files in the inbox are ignored)
- `deleteExtensions` = An array of file extensions that are deleted from the inbox if found (e.g. to remove clutter like 'txt' and 'nfo' files)

## Run

Simply run `node tvgeek.js` or `coffee tvgeek.coffee`, whichever flavour you prefer.

## Structure

The `structure` parameter in the config, defines the folder and file structure inside the library path. You specify a relative path that can contain the following placeholders:

- `%show%` = The title of the show
- `%show_sortable%` = The title of the show (lexically sortable, e.g. "The Simpsons" becomes "Simpsons, The")
- `%season%` = The season number of the episode
- `%season_00%` = The season number of the episode (always two digits)
- `%episode%` = The episode number (within the season) of the episode
- `%episode_00%` = The episode number (within the season) of the episode (always two digits)
- `%title%` = The title of the episode

Note: The file extension is always appended to the structure.

### Example: 
Your library folder is `/home/someone/tvshows`.
The structure is `%show_sortable%/Season %season%/%show% S%season_00%E%episode_00% %title%`.
One example episode will moved from the inbox to:
`/home/someone/tvshows/Simpsons, The/Season 25/The Simpsons S25E18 Days of Future Future.mkv`