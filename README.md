This repository aggregates configurations, scripts and tips for using [mpv](https://github.com/mpv-player/mpv) as an image viewer. The affectionate nickname `mvi` is given to mpv in such case.

This README assumes basic familiarity with mpv and its configuration. The information here should be platform-agnostic for the most part.

[![demo](https://i.vimeocdn.com/filter/overlay?src0=https%3A%2F%2Fi.vimeocdn.com%2Fvideo%2F674986351_1280x720.jpg&src1=https%3A%2F%2Ff.vimeocdn.com%2Fimages_v6%2Fshare%2Fplay_icon_overlay.png)](https://vimeo.com/249231479)

# Why?

mpv is a competent video player and sufficiently lightweight to use comfortably to view images. It features advanced scaling algorithms and color management, which are key features in an image viewer.  
It is also very extensible which allows us to compensate for some missing image viewer features easily.  
It won't compete with `feh` or the likes when it comes to size or startup time, but it is still plenty fast.

# Configuration

There are several options for making an mvi configuration.  
* Use the normal mpv config, and apply changes at runtime. You will need `detect-image.lua` and use [input sections](https://mpv.io/manual/master/#input-sections) and [profiles](https://mpv.io/manual/master/#profiles) to make this work.
* Or create an entirely separate `~/.config/mvi/` directory and use the alias `alias mvi='mpv --config-dir=$HOME/.config/mvi'` 

The first option is more complex, the second results in essentially two separate programs.

The examples `mpv.conf` and `input.conf` in this repository are commented to highlight (un)desirable settings.

# Scripts

## image-positioning.lua

Adds several high-level commands to zoom and pan:

`drag-to-pan`: pan the image with the cursor, while keeping the same part of the image under the cursor  
`pan-follows-cursor`: pan the image in the direction of the cursor  
`cursor-centric-zoom`: (de)zoom the video while keeping the same part of the image under the cursor  
`align-border`: align the border of the image with the border of the window  
`pan-image`: pan the image in a direction, optionally ignoring the zoom or forcing the image to stay visible  
`rotate-video`: rotate the image in 90 degrees increment  
`reset-pan-if-visible`: reset the pan if the entire image is visible  

There are no default bindings, see [`input.conf`](input.conf#L19-L67) for how to bind them.

## status-line.lua

Adds a status line that can show different properties in the corner of the window. By default it shows `filename [positon/total]` in the bottom left.

Can be activated with the commands `status-line-enable`, `status-line-disable`, `status-line-toggle` and configured through [`status_line.conf`](script-opts/status_line.conf).

## detect-image.lua

Allows you to run specific commands when images are being displayed. Does not do anything by default, needs to be configured through [`detect_image.conf`](script-opts/detect_image.conf).

For example, this makes it possible to setup bindings that are only in effect with images, like so:
```
command_on_first_image_loaded=enable-section image-viewer
command_on_non_image_loaded=disable-section image-viewer
```
Where the 'image-viewer' bindings are specified like so [`input.conf`](input.conf#L96-L99).

## minimap.lua

Adds a minimap that displays the position of the image relative to the view.  
Can be activated with `minimap-enable`, `minimap-disable`, `minimap-toggle` and configured through [`minimap.conf`](script-opts/minimap.conf).

## ruler.lua

Adds a `ruler` command that lets you measure positions, distances and angles in the image.
Can be configured through [`ruler.conf`](script-opts/ruler.conf).

## freeze-window.lua

By default, mpv automatically resizes the window when the current file changes to fit its size. This script freezes the window so that this does not happen. 
There is no configuration.

## Others

Some other mpv scripts work well with mvi, here are a few (feel free to send a PR for others):

[playlist-view](https://github.com/occivink/mpv-gallery-view): show all images in a grid view  
[zones](https://github.com/wiiaboo/mpv-scripts/blob/master/zones.lua): send different commands depending on cursor position  
[autoload](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autoload.lua): automatically load all files in the same directory. Set `videos=no` and `audio=no` in `script-opts/autoload.conf` to only autoload images.  
[delete-file](https://github.com/zenyd/mpv-scripts#delete-file): delete the current file  
[mpv_crop_script](https://github.com/TheAMM/mpv_crop_script): featureful screenshot tool  
[auto-profiles](https://github.com/wiiaboo/mpv-scripts/blob/master/auto-profiles.lua): apply profiles conditionally. Can be used to lower settings with huge images  
[crop](https://github.com/occivink/mpv-scripts#croplua): simple cropping script  
[playlist-manager](https://github.com/jonniek/mpv-playlistmanager): playlist management script  
[blacklist-extensions](https://github.com/occivink/mpv-scripts#blacklist-extensionslua): remove files from the playlist based on their types

# Credits

Thanks to haasn for coming up first with the [image-viewer config](https://gist.github.com/haasn/7919afd765e308fa91cbe19a64631d0f), all the mpv devs and the /mpv/ funposters.
