This repository aggregates configurations, scripts and tips for using [mpv](https://github.com/mpv-player/mpv) as an image viewer. The affectionate nickname `mvi` is given to mpv in such case.

This README assumes basic familiarity with mpv and its configuration. The information here should be platform-agnostic for the most part.

# Why?

mpv is a competent video player and sufficiently lightweight to use comfortably to view images. It features advanced scaling algorithms and color management, which are key features in an image viewer.  
It is also very extensible which allows us to compensate for some missing image viewer features easily.  
It won't compete with `feh` or the likes when it comes to size or startup time, but it is still plenty fast.

# Configuration

There are several options for making an mvi configuration.  
* You can create an entirely separate `~/.config/mvi/` directory and use the alias `alias mvi='mpv --config-dir=$HOME/.config/mvi'` 
* Or keep a separate profile in your mpv config and alias it like that `alias mvi=mpv --profile=image'`. 

The first option can be cleaner, at the cost of some duplication.

The examples `mpv.conf` and `input.conf` in this repository are commented to highlight (un)desirable settings.

# Scripts

## image-viewer.lua

The `scripts/image-viewer.lua` script offers several commands that are common in image viewers:

`drag-to-pan`: pan the image with the cursor, while keeping the same part of the image under the cursor  
`pan-follows-cursor`: pan the image in the direction of the cursor  
`cursor-centric-zoom`: (de)zoom the video while keeping the same part of the image under the cursor  
`align-border`: align the border of the image with the border of the window  
`zoom-invariant-add`: pan the image by the same amount, regardless of the zoom  
`rotate-video`: rotate the image in 90 degrees increment  
`reset-pan-if-visible`: reset the pan if the entire image is visible  

They don't have any default bindings, see the example `input.conf`, and in the configuration bind them.
Some of these commands can be configured, see `lua-settings/image_viewer.conf` in this repo for the options available. 

## gallery.lua

The [gallery-view](https://github.com/occivink/mpv-gallery-view) plugin greatly helps when navigating large image playlists.

## Others

Some other mpv scripts work well with mvi, here are a few (feel free to send a PR for others):

[zones](https://github.com/wiiaboo/mpv-scripts/blob/master/zones.lua): send different commands depending on cursor position  
[delete-file](https://github.com/zenyd/mpv-scripts#delete-file): delete the current file  
[mpv_crop_script](https://github.com/TheAMM/mpv_crop_script): featureful screenshot tool  
[auto-profiles](https://github.com/wm4/mpv-scripts/blob/master/auto-profiles.lua): apply profiles conditionally. Can be used to lower settings with huge images  
[crop](https://github.com/occivink/mpv-scripts#croplua): simple cropping script  
[autoload](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autoload.lua): automatically load all files in the same directory  
[playlist-manager](https://github.com/jonniek/mpv-playlistmanager): playlist management script  
[mpv-stats](https://github.com/Argon-/mpv-stats): show some info about the input file (integrated into mpv in 0.28+)  

# TODO

`input.conf` that mirror the bindings of popular image viewing software, such as `feh` or `sxiv`.

Configuration with no terminal output except for the path when pressing `ENTER` so that you can pipe mvi to other commands.

# Credits

Thanks to haasn for coming up first with the [image-viewer config](https://gist.github.com/haasn/7919afd765e308fa91cbe19a64631d0f), all the mpv devs and the /mpv/ shitposters.
