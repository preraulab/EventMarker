# eventmarker

Interactive event marker manager for MATLAB plots. Lets a user mark, label, drag, resize, save, and reload events on top of any 2-D plot — with full support for both numeric and `datetime` x-axes.

Designed for sleep / time-series work where a scorer is reviewing a spectrogram or a waveform and wants to flag instants (onsets, artifacts) or intervals (REM epochs, arousals, artifact regions) and later consume them programmatically.

## Components

| Class | Role |
|---|---|
| `EventMarker` | Main orchestrator. Attaches to an axes, owns the event list, handles mouse/keyboard, manages selection. |
| `EventObject` | Value class describing either an event *type* (name, ID, region-vs-point, constrain flag) or a placed instance (also carries graphics handles + unique `event_ID`). |
| `DateTimeLine` | Draggable vertical line primitive used for *point* events. Works with both numeric and datetime axes. |
| `DateTimeRectangle` | Draggable, resizable rectangle primitive used for *region* events. Works with both numeric and datetime axes. |

## Entry point

```matlab
marker = EventMarker(ax, xbounds, ybounds, event_types, event_list, line_colors, font_size)
```

All arguments optional — `ax` defaults to `gca`, bounds default to the current axis limits, colors to the axes ColorOrder, font size to 12.

| Argument | Meaning |
|---|---|
| `ax` | axes handle to attach to |
| `xbounds` | `[xmin xmax]` limits within which markers may be placed |
| `ybounds` | `[ymin ymax]` limits for marker placement |
| `event_types` | array of `EventObject`s describing the palette (REM, Spindle, Artifact, …) |
| `event_list` | optional pre-existing events to reload (e.g. from a prior save) |
| `line_colors` | `Nx3` color per type |
| `font_size` | label font size |

## Event types vs. events

An `EventObject` plays two roles:

1. **Type definition** — created once per marker category. Carries `name`, `type_ID`, `region` (true = rectangle, false = line), and `constrain` (for regions, whether they span the full y-axis vertically or can be drawn at arbitrary height).
2. **Placed instance** — created each time the user marks an event. Shares the type's fields plus a unique `event_ID` (random UUID-like int) and the live graphics handles (`obj_handle`, `label_handle`).

Build a palette once, hand it to `EventMarker`, and it takes care of instance creation from there.

## Interaction model

- **Place** — press a hotkey assigned to a type, then click once (point) or click twice (region start/end).
- **Select/edit** — double-click an existing event to enter edit mode: `DateTimeLine` / `DateTimeRectangle` becomes interactive (drag to move, drag edges to resize).
- **Delete** — select an event then press Backspace/Delete.
- **Save/Load** — via menu or Ctrl+S / Ctrl+L. Persists the `event_list` as `.mat` for later reload.

The actual hotkey mapping (1/2/3/4/Space) lives in the *viewer script*, not in `EventMarker` — keeping the marker class hotkey-agnostic so each viewer can define its own bindings.

## DateTime support

`DateTimeLine` and `DateTimeRectangle` both detect whether the parent axes uses datetime x-values and transform interactively between screen pixels and datetime values. This is the key value-add over a plain draggable ROI: datetime axes aren't natively editable by MATLAB's `drawline` / `drawrectangle`.

## Demo

```matlab
cd eventmarker/example_viewer
basic_viewer
```

The demo creates a two-panel figure (pseudo-spectrogram on top, time-series below), attaches an `EventMarker` to the top axes, and wires up four event types plus save/load:

| Hotkey | Action |
|---|---|
| `1` | Mark REM region (full-height, constrained) |
| `2` | Mark "Eyes Closed" point |
| `3` | Mark Alpha region (unconstrained height) |
| `4` | Mark Arousal point |
| Space | Add a free-text annotation |
| Backspace / Delete | Delete selected event |
| Ctrl+S | Save events |
| Ctrl+L | Load events |
| Double-click event | Enter edit mode |

## Typical viewer-script skeleton

```matlab
% 1. Build your figure + axes
f  = figure;
ax = axes(f);
imagesc(t, f_vec, S); axis xy

% 2. Define event-type palette
types = [ ...
    EventObject('REM',         1, true,  true ); ...   % region, full-height
    EventObject('EyesClosed',  2, false, false); ...   % point
    EventObject('Alpha',       3, true,  false); ...   % region, free-height
    EventObject('Arousal',     4, false, false) ];     % point

colors = lines(numel(types));

% 3. Attach marker
marker = EventMarker(ax, [t(1) t(end)], ylim(ax), types, [], colors, 12);

% 4. Install a KeyPressFcn that calls marker.addEvent(type_ID) for your hotkeys
f.KeyPressFcn = @(s,e) my_hotkey_handler(marker, e);

% 5. After scoring, read back:
events = marker.event_list;   % EventObject array
```

## Files in this directory

- `EventMarker.m` — orchestrator class (entry point)
- `EventObject.m` — type definition + placed-instance record
- `DateTimeLine.m` — draggable line primitive (datetime-aware)
- `DateTimeRectangle.m` — draggable/resizable rectangle primitive (datetime-aware)
- `example_viewer/basic_viewer.m` — runnable demo
- `README.md` — this file

## Dependencies

Base MATLAB only. No toolboxes required. `basic_viewer.m` uses `figdesign` and `suptitle` from `utils/` for layout but the core classes do not.
