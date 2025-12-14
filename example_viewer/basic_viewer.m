% basic_viewer - Example viewer demonstrating EventMarker usage
%
% This function creates a simple two-panel figure with a spectrogram-like
% image on top and a time-series plot below. It initializes an EventMarker
% object on the top axes for interactive event marking (regions and points).
%
% Features demonstrated:
% - Adding event types (regions and points)
% - Interactive marking via hotkeys
% - Deleting selected events (Backspace/Delete)
% - Adding free-text annotations (Space bar)
% - Save/Load events via menu
% - Linked scrolling/zooming/panning
%
% Hotkeys (printed to command window on startup):
%   1 - Mark REM region (constrained full-height)
%   2 - Mark Eyes Closed point
%   3 - Mark Alpha region (unconstrained height)
%   4 - Mark Arousal point
%   Space - Add text annotation
%   Backspace/Delete - Delete selected event (after double-click selection)
%   Ctrl+S - Save events
%   Ctrl+L - Load events
%
% Copyright 2024 Michael J. Prerau Laboratory - http://www.sleepEEG.org
% ********************************************************************
clear all;
close all;

%************************************************************
% PRINT HOTKEY HELP TO COMMAND WINDOW
%************************************************************
fprintf('\n=== EventMarker Hotkeys ===\n');
fprintf('1 : Mark REM region (full-height)\n');
fprintf('2 : Mark Eyes Closed point\n');
fprintf('3 : Mark Alpha region (free height)\n');
fprintf('4 : Mark Arousal point\n');
fprintf('Space : Add free-text annotation\n');
fprintf('Backspace / Delete : Delete selected event\n');
fprintf('Ctrl+S : Save events (or use Markers menu)\n');
fprintf('Ctrl+L : Load events (or use Markers menu)\n');
fprintf('Double-click an event to select/edit it\n');
fprintf('==============================\n\n');

%************************************************************
% CREATE FIGURE AND AXES
%************************************************************
f = figure('Color', 'w', 'Visible', 'on', 'Units', 'normalized');

% Create two axes with custom layout (assuming figdesign helper exists)
ax = figdesign(2, 1, 'margins', [.05, .15, .05, .05, .05]);

N = 60 * 8;  % 8 hours of minutes
x = datetime('12-Dec-2025 22:15:20') + minutes(1:N);

% Top panel: spectrogram-like image
subplot(ax(1))
imagesc(x, 1:N, peaks(N));
axis xy
axis tight
suptitle('Spectrogram')

% Bottom panel: time-domain signal
subplot(ax(2))
plot(x, randn(1, N));
axis tight
title('Time Series')

% Link x-axes for synchronized zooming/panning
linkaxes(ax, 'x');

%************************************************************
% INITIALIZE EVENTMARKER
%************************************************************
% Create EventMarker on the top (image) axes
em = EventMarker(ax(1));

% Add the EventMarker's internal axes to the link group
ax = [ax em.main_ax em.label_ax];

%************************************************************
% DEFINE EVENT TYPES
%************************************************************
% add_event_type(EventObject(name, type_ID, region, constrain))
%
% - region    = true  -> rectangular region (DateTimeRectangle)
% - region    = false -> vertical line (DateTimeLine)
% - constrain = true  -> region spans full axis height
em.add_event_type(EventObject('REM',          10, true,  true));  % Full-height region
em.add_event_type(EventObject('Eyes Closed',  3, false, false)); % Point marker
em.add_event_type(EventObject('Alpha',        5, true,  false)); % Free-height region
em.add_event_type(EventObject('Arousal',      4, false, false)); % Point marker

%************************************************************
% ENABLE INTERACTIVE SCROLL/ZOOM/PAN
%************************************************************
scrollzoompan(ax(1));  % Custom helper for mouse wheel zoom & pan

% Link all axes (including label_ax) for synchronized view
linkaxes(ax, 'x');

%%Bulk add annotations
N = 5;
annotation_time = linspace(x(1), x(end),N);
annotation_text = strcat('Annot. #', string(1:N));
em.add_annotation(annotation_text, annotation_time);
%************************************************************
% KEYBOARD SHORTCUTS AND MENU
%************************************************************
set(f, 'KeyPressFcn', @(src, event) handle_keys(event, em));

% Menu for saving/loading events
m = uimenu(f, 'Label', 'Markers');
uimenu(m, 'Label', 'Save Events...', 'Callback', @(src, ~) em.save(), ...
    'Accelerator', 's');
uimenu(m, 'Label', 'Load Events...', 'Callback', @(src, ~) em.load(), ...
    'Accelerator', 'l');

%************************************************************
% HANDLE HOTKEYS
%************************************************************
function handle_keys(event, em)
% handle_keys - Process keyboard shortcuts for event marking
%
% Called on every key press in the figure.
%
% Supported keys:
%   Backspace/Delete - Delete currently selected event
%   '1'              - Mark REM region
%   '2'              - Mark Eyes Closed point
%   '3'              - Mark Alpha region
%   '4'              - Mark Arousal point
%   Space            - Add free-text annotation

switch event.Key
    case {'backspace', 'delete'}
        em.delete_selected();
end

if isempty(event.Character)
    return;
end

switch lower(event.Character)
    case '1'
        em.mark_event(10);  % REM region
    case '2'
        em.mark_event(3);   % Eyes Closed
    case '3'
        em.mark_event(5);   % Alpha region
    case '4'
        em.mark_event(4);   % Arousal
    case ' '
        % Prompt for annotation text
        prompt = {'Enter annotation text:'};
        dlgtitle = 'Annotation Input';
        dims = [1 50];
        definput = {''};
        answer = inputdlg(prompt, dlgtitle, dims, definput);
        if ~isempty(answer) && ~isempty(answer{1})
            em.add_annotation(answer{1});
        end
end
end
