# Movie Library

Movie Library is a Markdown-first Obsidian plugin for tracking movies and series. It keeps all new data beneath one configurable root, defaults to `Movie Library`, and does not alter existing media folders.

## Use

Open **Movie Library: Open dashboard**. Use **Look up media** when an optional OMDb key is configured, or **Manual entry** at any time. The dashboard provides an artwork gallery, filters, personal tracking, family guidance, and a rule-based **What should we watch?** picker.

Each note stores a remote poster URL but never downloads image files. A missing or offline poster falls back to a local placeholder. OMDb is optional; without a key, manual entry and every local dashboard feature continue to work.

## Custom lists

The built-in Watchlist remains separate. Use the **Custom lists** field while adding or editing a title for collections such as `Family favorites`, `Date night`, or `World War II`. Movie Library saves each membership as a standard Markdown tag, for example `#movie-library/list/family-favorites`. This keeps lists portable, searchable, and visible in Obsidian's native tag tools. Type a new list name freely or reuse one shown beneath the field.

## Optional Plex sync

Movie Library can make a one-way import from Plex. Configure the Plex server URL and token in **Settings**, choose the movie and series libraries to include, then use **Sync now** (or the **Movie Library: Sync from Plex** command). The sync creates or updates Markdown records for titles available in Plex and brings across watched state, last-watched date, Plex user rating when present, metadata, and a token-free artwork path.

Plex never becomes the source for your watchlist, favorite/owned flags, family guide, or personal notes. The token is stored in Obsidian's local plugin settings; it is not written into notes. For iOS, the configured server URL must be a LAN address your phone can reach—`localhost` only works on the computer running Plex.

## Family guide

Each note includes a household-managed family decision, suggested age, five content-concern levels, notes, and discussion prompts. The **Guide** button opens the applicable IMDb Parents Guide in your browser when an IMDb ID exists. Movie Library does not scrape or copy parental-guide content.

## Privacy and limits

Records are ordinary Markdown notes. Plugin settings, including an optional OMDb key, are stored locally by Obsidian and are not encrypted by this plugin. External lookup, poster display, and research links require a network connection.

## Development

Run `npm install`, then `npm test`. Copy `main.js`, `manifest.json`, and `styles.css` into `.obsidian/plugins/movie-library/` to install manually.
