classdef EventMarker < handle
    % EventMarker - Interactive event marker manager for MATLAB plots
    %
    % This class allows users to interactively add, edit, and manage event markers
    % (vertical lines or rectangular regions) on a plot axis. It supports both numeric
    % and datetime x-axes seamlessly. Markers are organized by user-defined event types,
    % each with a name, ID, color, and optional label. Double-clicking an existing marker
    % enables interactive dragging/resizing using DateTimeLine or DateTimeRectangle objects.
    %
    % Usage:
    %   obj = EventMarker(event_axis, xbounds, ybounds, event_types, event_list, line_colors, font_size)
    %
    % Inputs:
    %   event_axis   - Handle to the target axes (default: gca)
    %   xbounds      - [xmin xmax] limits for marker placement (default: axis XLim)
    %   ybounds      - [ymin ymax] limits for marker placement (default: axis YLim)
    %   event_types  - Array of event type structures (see below)
    %   event_list   - Previously saved event array (default: empty)
    %   line_colors  - Nx3 color matrix for event types (default: axes ColorOrder)
    %   font_size    - Font size for event labels (default: 12)
    %
    % Event type structure fields:
    %   .name       - String label displayed above marker
    %   .type_ID    - Unique integer identifier
    %   .region     - Logical: true for rectangular region, false for vertical line
    %   .constrain  - Logical: if true and region, rectangle spans full ybounds
    %
    % Properties (Access = public):
    %   main_ax         - Axes containing the marker graphics
    %   label_ax        - Invisible overlay axes for text labels
    %   xbounds         - [xmin xmax] placement limits
    %   ybounds         - [ymin ymax] placement limits
    %   event_types     - Array of defined event type structures
    %   event_list      - Array of placed event objects
    %   colors          - Nx3 matrix of colors for each event type
    %   label_fontsize  - Font size for labels
    %   selected_ind    - Index of currently selected event (for external reference)
    %
    % Example:
    %   See basic_viewer.m for a complete demonstration.
    %
    % Michael J. Prerau Laboratory - http://www.sleepEEG.org
    % ********************************************************************

    %************************************************************
    % PROPERTIES
    %************************************************************
    properties (Access = public)
        main_ax         % Axes containing the marker graphics
        label_ax        % Invisible overlay axes holding text labels
        xbounds         % [xmin xmax] limits constraining marker placement
        ybounds         % [ymin ymax] limits constraining marker placement
        event_types     % Array of event type definition structures
        event_list = -99; % Array of placed event objects (initialized to flag empty state)
        colors          % Nx3 matrix of colors corresponding to event_types
        label_fontsize  % Font size for event name labels
        selected_ind = [] % Index of currently selected/edited event
    end

    properties (Access = private)
        main_fig                % Parent figure of the main axes
        current_object = []     % Active interactive editor (DateTimeLine or DateTimeRectangle)
        current_object_ind = [] % Index of the event currently being edited
        adding_points = false   % Flag indicating click-collection mode
        num_clicks = 0          % Counter for collected clicks
        mouse_point             % Most recent mouse click position [x y]
        clickTimer              % Timer object for double-click detection
        doubleClickDelay = 0.25 % Maximum delay (seconds) between clicks to register double-click
    end

    %%%%%%%%%%%%%%% PUBLIC METHODS %%%%%%%%%%%%%%%%%%%%%%
    methods (Access = public)

        %***********************************************
        % CONSTRUCTOR
        %***********************************************
        function obj = EventMarker(varargin)
            % EventMarker constructor
            %
            % Creates the EventMarker object, sets up axes, and installs mouse callbacks.
            %
            % Inputs:
            %   event_axis, xbounds, ybounds, event_types, event_list,
            %   line_colors, font_size (optional; defaults provided)
            
            % Default arguments
            args = {gca, [], [], [], [], get(gca,'ColorOrder'), 12};
            % Override defaults with provided non-empty inputs
            args(~cellfun('isempty', varargin)) = varargin(~cellfun('isempty', varargin));
            [obj.main_ax, obj.xbounds, obj.ybounds, obj.event_types, ...
             obj.event_list, obj.colors, obj.label_fontsize] = args{:};
            
            % Use axis limits if bounds not provided
            if isempty(obj.xbounds)
                obj.xbounds = obj.main_ax.XLim;
            end
            if isempty(obj.ybounds)
                obj.ybounds = obj.main_ax.YLim;
            end
            
            % Store parent figure and install click callback
            obj.main_fig = get(obj.main_ax, 'Parent');
            set(obj.main_fig, 'Units', 'normalized', ...
                'WindowButtonDownFcn', @obj.clickcallback);
            
            % Configure main axes
            set(obj.main_ax, 'NextPlot', 'replacechildren', 'Units', 'normalized');
            
            % Create invisible overlay axes for labels
            pos = get(obj.main_ax, 'Position');
            pos(2) = pos(2) + pos(4) + 0.02;  % Place just above main axes
            pos(4) = 1e-9;                    % Minimal height
            obj.label_ax = axes('Position', pos, 'Visible', 'off', ...
                                'XTick', [], 'YTick', []);
            
            % Ensure label_ax supports datetime if main_ax does
            xl = obj.main_ax.XLim;
            if isdatetime(xl)
                h = plot(obj.label_ax, xl, [0 0], 'w');  % Dummy plot to force datetime
                delete(h);
            end
            
            % Link x-axes and match limits
            linkaxes([obj.main_ax obj.label_ax], 'x');
            xlim(obj.label_ax, xl);
            obj.label_ax.Visible = 'off';
        end

        %-----------------------------------------------------------
        % ADD EVENT TYPE
        %-----------------------------------------------------------
        function add_event_type(obj, event_obj)
            % add_event_type - Register a new event type
            %
            % Inputs:
            %   event_obj - Structure with fields: name, type_ID, region, constrain
            %
            % Checks for duplicate name or type_ID and warns if found.
            
            if isempty(obj.event_types)
                obj.event_types = event_obj;
            else
                % Check name uniqueness
                if any(strcmpi({obj.event_types.name}, event_obj.name))
                    warning(['Event type not added. Name "' event_obj.name '" already exists.']);
                    return;
                end
                % Check ID uniqueness
                if any([obj.event_types.type_ID] == event_obj.type_ID)
                    warning(['Event type "' event_obj.name '" not added. ID "' num2str(event_obj.type_ID) '" already exists.']);
                    return;
                end
                % Append if unique
                obj.event_types(end+1) = event_obj;
            end
        end

        %-----------------------------------------------------------
        % GET EVENTS
        %-----------------------------------------------------------
        function [etimes, etypes, eIDs, isregion] = get_events(obj)
            % get_events - Retrieve sorted event information
            %
            % Outputs:
            %   etimes    - Event times (single) or region midpoints, sorted chronologically
            %   etypes    - Corresponding type_ID for each event
            %   eIDs      - Unique event_ID for each event
            %   isregion  - Logical indicating whether event is a region
            
            if isempty(obj.event_list) || isequal(obj.event_list, -99)
                etimes = []; etypes = []; eIDs = []; isregion = [];
                return;
            end
            
            etypes   = [obj.event_list.type_ID];
            eIDs     = [obj.event_list.event_ID];
            isregion = [obj.event_list.region];
            
            % Extract times (single events) or midpoints (regions)
            single_inds = find(~isregion);
            region_inds = find(isregion);
            etimes_raw = [];
            
            if ~isempty(single_inds)
                etimes_raw = cellfun(@(h) h.XData(1), {obj.event_list(single_inds).obj_handle});
            end
            if ~isempty(region_inds)
                region_centers = zeros(1, numel(region_inds));
                for k = 1:numel(region_inds)
                    p = get(obj.event_list(region_inds(k)).obj_handle, 'Position');
                    region_centers(k) = p(1) + p(3)/2;
                end
                etimes_raw = [etimes_raw region_centers];
            end
            
            [etimes, sort_idx] = sort(etimes_raw);
            etypes    = etypes(sort_idx);
            eIDs      = eIDs(sort_idx);
            isregion  = isregion(sort_idx);
        end

        %-----------------------------------------------------------
        % MARK SINGLE EVENT (INTERACTIVE)
        %-----------------------------------------------------------
        function new_event = mark_event(obj, varargin)
            % mark_event - Interactively place a single event marker
            %
            % Usage:
            %   mark_event(obj, type_ID)                    - Interactive placement
            %   mark_event(obj, type_ID, position_array)    - Programmatic (calls mark_events)
            %
            % For interactive mode, clicks define the marker position.
            
            if numel(varargin) == 2
                obj.mark_events(varargin{:});
                new_event = [];
                return;
            else
                event_type_id = varargin{1};
            end
            
            % Validate type_ID
            if isempty(obj.event_types)
                error('No event types defined.');
            end
            event_ind = [obj.event_types.type_ID] == event_type_id;
            if ~any(event_ind)
                error(['Event ID ' num2str(event_type_id) ' is invalid.']);
            end
            
            new_event = obj.event_types(event_ind);
            event_type = obj.event_types(event_ind);
            
            if event_type.region
                % Interactive region placement
                points = obj.get_clicks(2);
                xstart = [points{1,1} points{2,1}];
                ystart = [points{1,2} points{2,2}];
                
                if event_type.constrain
                    rect_pos = [min(xstart) obj.ybounds(1) abs(diff(xstart)) diff(obj.ybounds)];
                else
                    rect_pos = [min(xstart) min(ystart) abs(diff(xstart)) abs(diff(ystart))];
                end
                
                new_event.obj_handle = rectangle('Parent', obj.main_ax, ...
                    'Position', rect_pos, 'EdgeColor', obj.colors(event_ind,:), ...
                    'LineWidth', 4, 'FaceColor', 'none');
                obj_middle = mean([rect_pos(1) rect_pos(1)+rect_pos(3)]);
            else
                % Single-time event
                pos = obj.get_clicks(1);
                xpos = pos{1};
                line_y = obj.main_ax.YLim;
                new_event.obj_handle = line([xpos xpos], line_y, ...
                    'Parent', obj.main_ax, 'Color', obj.colors(event_ind,:), ...
                    'LineWidth', 4);
                obj_middle = xpos;
            end
            
            % Add label if name exists
            if ~isempty(new_event.name)
                new_event.label_handle = text(obj.label_ax, obj_middle, 0, new_event.name, ...
                    'FontSize', obj.label_fontsize, 'VerticalAlignment', 'top', ...
                    'Color', 'k', 'HorizontalAlignment', 'center');
                if event_type.region && event_type.constrain
                    set(new_event.label_handle, 'VerticalAlignment', 'bottom');
                end
            end
            
            % Assign unique ID and append to list
            new_event.event_ID = randi(intmax);
            if isempty(obj.event_list) || isequal(obj.event_list, -99)
                obj.event_list = new_event;
            else
                obj.event_list(end+1) = new_event;
            end
            
            set(gcf, 'Pointer', 'arrow');
        end

        %-----------------------------------------------------------
        % MARK MULTIPLE EVENTS (PROGRAMMATIC)
        %-----------------------------------------------------------
        function new_event = mark_events(obj, event_type_id, position)
            % mark_events - Programmatically place multiple events of same type
            %
            % Inputs:
            %   event_type_id - Integer ID of event type
            %   position      - Nx1 (lines) or Nx4 (rectangles) array of positions
            
            if isempty(obj.event_types)
                error('No event types defined.');
            end
            event_ind = [obj.event_types.type_ID] == event_type_id;
            if ~any(event_ind)
                error(['Event ID ' num2str(event_type_id) ' is invalid.']);
            end
            
            num_events = size(position, 1);
            old_size = length(obj.event_list);
            if ~isempty(obj.event_list) && ~isequal(obj.event_list, -99)
                obj.event_list(old_size + num_events) = obj.event_list(1);  % Pre-allocate
            end
            
            for ii = 1:num_events
                new_event = obj.event_types(event_ind);
                if new_event.region
                    rect_pos = position(ii,:);
                    new_event.obj_handle = rectangle('Parent', obj.main_ax, ...
                        'Position', rect_pos, 'EdgeColor', obj.colors(event_ind,:), ...
                        'LineWidth', 4, 'FaceColor', 'none');
                    obj_middle = mean(rect_pos(1) + [0 rect_pos(3)]);
                else
                    xpos = position(ii,1);
                    line_y = obj.main_ax.YLim;
                    new_event.obj_handle = line([xpos xpos], line_y, ...
                        'Parent', obj.main_ax, 'Color', obj.colors(event_ind,:), ...
                        'LineWidth', 4);
                    obj_middle = xpos;
                end
                
                if ~isempty(new_event.name)
                    new_event.label_handle = text(obj.label_ax, obj_middle, 0, new_event.name, ...
                        'FontSize', obj.label_fontsize, 'VerticalAlignment', 'top', ...
                        'Color', 'k', 'HorizontalAlignment', 'center');
                    if new_event.region && new_event.constrain
                        set(new_event.label_handle, 'VerticalAlignment', 'bottom');
                    end
                end
                
                new_event.event_ID = randi(intmax);
                obj.event_list(old_size + ii) = new_event;
            end
        end

        %-----------------------------------------------------------
        % ADD ANNOTATION
        %-----------------------------------------------------------
        function new_event = add_annotation(obj, annotation_text, time)
            % add_annotation - Place a free-text annotation marker
            %
            % Inputs:
            %   annotation_text - String to display
            %   time            - Optional x-position (interactive click if omitted)
            
            new_event = AnnotationObject(annotation_text);
            
            if nargin < 3
                obj.get_clicks(1);
                time = obj.mouse_point(1);
            end
            xpos = time;
            
            if isdatetime(xpos)
                xpos = obj.dt2pos(xpos);
            end

            line_y = obj.main_ax.YLim;
            new_event.obj_handle = line([xpos xpos], line_y, ...
                'Parent', obj.main_ax, 'Color', 'k', 'LineWidth', 4);
            obj_middle = xpos;
            
            new_event.label_handle = text(obj.label_ax, obj_middle, 0, new_event.name, ...
                'FontSize', obj.label_fontsize, 'VerticalAlignment', 'top', ...
                'Color', 'k', 'HorizontalAlignment', 'center');
            
            if isempty(obj.event_list) || isequal(obj.event_list, -99)
                obj.event_list = new_event;
            else
                obj.event_list(end+1) = new_event;
            end
        end

        %-----------------------------------------------------------
        % DELETE SELECTED EVENT
        %-----------------------------------------------------------
        function delete_selected(obj)
            % delete_selected - Remove the currently selected/edited event
            
            if ~isempty(obj.current_object)
                selected_obj = obj.event_list(obj.current_object_ind);
                label_handle  = selected_obj.label_handle;
                graphics_obj  = selected_obj.obj_handle;
                
                % Delete interactive editor if present
                if isvalid(obj.current_object)
                    delete(obj.current_object);
                end
                
                % Delete static graphics and label
                if isvalid(graphics_obj)
                    delete(graphics_obj);
                end
                if ~isempty(label_handle) && isvalid(label_handle)
                    delete(label_handle);
                end
                
                % Remove from event list
                if numel(obj.event_list) > 1
                    obj.event_list(obj.current_object_ind) = [];
                else
                    obj.event_list = [];
                end
                
                % Clear selection state
                obj.current_object = [];
                obj.current_object_ind = [];
                obj.selected_ind = [];
            end
        end

        %-----------------------------------------------------------
        % SAVE EVENT DATA
        %-----------------------------------------------------------
        function save(obj, fname)
            % save - Export event positions and types to .mat file
            %
            % Inputs:
            %   fname - Optional filename (dialog if omitted)
            
            if isempty(obj.event_list) || isequal(obj.event_list, -99)
                warning('No events to save.');
                return;
            end
            
            event_data = cell(1, numel(obj.event_types));
            for type_idx = 1:numel(obj.event_types)
                type_ID = obj.event_types(type_idx).type_ID;
                idxs = find([obj.event_list.type_ID] == type_ID);
                
                for ev = 1:numel(idxs)
                    ev_obj = obj.event_list(idxs(ev));
                    if obj.event_types(type_idx).region
                        pos = get(ev_obj.obj_handle, 'Position');
                        x_bounds = [pos(1) pos(1)+pos(3)];
                        if obj.event_types(type_idx).constrain
                            event_data{type_idx}(ev,:) = x_bounds;
                        else
                            y_bounds = [pos(2) pos(2)+pos(4)];
                            event_data{type_idx}(ev,:) = [x_bounds y_bounds];
                        end
                    else
                        event_data{type_idx}(ev,1) = ev_obj.obj_handle.XData(1);
                    end
                end
            end
            
            event_types = obj.event_types;
            
            if nargin < 2 || isempty(fname)
                [filename, pathname] = uiputfile('saved_events.mat', 'Save Event Data');
                if filename == 0, return; end
                save(fullfile(pathname, filename), 'event_types', 'event_data');
            else
                save(fname, 'event_types', 'event_data');
            end
        end

        %-----------------------------------------------------------
        % LOAD EVENT DATA
        %-----------------------------------------------------------
        function load(obj, fname)
            % load - Import previously saved event data
            %
            % Inputs:
            %   fname - Optional filename (dialog if omitted)
            
            if nargin < 2 || isempty(fname)
                [filename, pathname] = uigetfile('*.mat', 'Select Event File');
                if filename == 0, return; end
                fullpath = fullfile(pathname, filename);
            else
                fullpath = fname;
            end
            
            S = load(fullpath);
            if ~all(isfield(S, {'event_types', 'event_data'}))
                error('Invalid event file: missing required variables.');
            end
            event_types = S.event_types;
            event_data  = S.event_data;
            
            % Validate loaded types match current ones
            for ii = 1:numel(obj.event_types)
                data = event_data{ii};
                if isempty(data), continue; end
                
                if obj.event_types(ii).region
                    pos_matrix = zeros(size(data,1), 4);
                else
                    pos_matrix = zeros(size(data,1), 1);
                end
                
                for j = 1:size(data,1)
                    raw = data(j,:);
                    if obj.event_types(ii).region
                        if obj.event_types(ii).constrain
                            pos_matrix(j,:) = [min(raw(1:2)) obj.ybounds(1) abs(diff(raw(1:2))) diff(obj.ybounds)];
                        else
                            pos_matrix(j,:) = [min(raw(1:2)) min(raw(3:4)) abs(diff(raw(1:2))) abs(diff(raw(3:4)))];
                        end
                    else
                        pos_matrix(j,1) = raw;
                    end
                end
                obj.mark_events(obj.event_types(ii).type_ID, pos_matrix);
            end
        end
    end

    %%%%%%%%%%%%%%% PRIVATE METHODS %%%%%%%%%%%%%%%%%%%%%%
    methods (Access = private)

        %-----------------------------------------------------------
        % MOUSE CLICK CALLBACK AND DOUBLE-CLICK HANDLING
        %-----------------------------------------------------------
        function clickcallback(obj, ~, ~)
            % Primary mouse button down callback
            if obj.adding_points
                cp = get(obj.main_ax, 'CurrentPoint');
                obj.mouse_point = cp(1,1:2);
                uiresume(obj.main_fig);
                return;
            end
            
            % Double-click detection via timer
            if isempty(obj.clickTimer) || ~isvalid(obj.clickTimer)
                obj.startSingleClickTimer();
            else
                obj.cancelSingleClickTimer();
                obj.handleDoubleClick();
            end
        end

        function startSingleClickTimer(obj)
            obj.clickTimer = timer('StartDelay', obj.doubleClickDelay, ...
                'TimerFcn', @(~,~) obj.handleSingleClick());
            start(obj.clickTimer);
        end

        function cancelSingleClickTimer(obj)
            if ~isempty(obj.clickTimer) && isvalid(obj.clickTimer)
                stop(obj.clickTimer);
                delete(obj.clickTimer);
                obj.clickTimer = [];
            end
        end

        function handleSingleClick(obj)
            % Placeholder for single-click actions (currently none)
            obj.clickTimer = [];
        end

        function handleDoubleClick(obj)
            cp = get(obj.main_ax, 'CurrentPoint');
            obj.mouse_point = cp(1,1:2);
            obj.edit_event();
        end

        %-----------------------------------------------------------
        % INTERACTIVE EDITING OF EXISTING EVENT
        %-----------------------------------------------------------
        function edit_event(obj, ~)
            % Toggle interactive editing on double-click
            if isempty(obj.event_list) || isequal(obj.event_list, -99)
                set(gcf, 'Pointer', 'arrow');
                return;
            end
            
            if isempty(obj.current_object)
                % Find closest event to click
                click_x = obj.mouse_point(1);
                min_dist = inf;
                closest_ind = [];
                for ii = 1:numel(obj.event_list)
                    tb = obj.event_list(ii).time_bounds();
                    if isdatetime(tb)
                        tb = obj.dt2pos(tb);
                    end
                    if isscalar(tb)
                        dist = abs(click_x - tb);
                    else
                        dist = min(abs(click_x - tb));
                    end
                    if dist < min_dist
                        min_dist = dist;
                        closest_ind = ii;
                    end
                end
                
                if isempty(closest_ind)
                    set(gcf, 'Pointer', 'arrow');
                    return;
                end
                
                obj.selected_ind = closest_ind;
                ev = obj.event_list(closest_ind);
                set(ev.obj_handle, 'Visible', 'off');
                
                if ev.region
                    pos = get(ev.obj_handle, 'Position');
                    posStruct.x      = obj.pos2dt(pos(1));
                    posStruct.width  = obj.pos2dt(pos(3)) - obj.pos2dt(0);
                    posStruct.y      = pos(2);
                    posStruct.height = pos(4);
                    
                    editor = DateTimeRectangle(obj.main_ax, posStruct, [], ...
                        'ConstrainToAxis', true, 'FullHeight', logical(ev.constrain));
                else
                    xpos = ev.obj_handle.XData(1);
                    posStruct.x1 = xpos;
                    posStruct.x2 = xpos;
                    posStruct.y1 = obj.ybounds(1);
                    posStruct.y2 = obj.ybounds(2);
                    
                    editor = DateTimeLine(obj.main_ax, posStruct, [], ...
                        'ConstrainToAxis', true, 'FullHeight', true);
                end
                
                editor.LineWidth = ev.obj_handle.LineWidth;
                editor.LineColor = [0 0 0];
                editor.UserCallback = @(src,evt) obj.label_follow(ev.label_handle, editor);
                
                obj.current_object = editor;
                obj.current_object_ind = closest_ind;
                
                set(ev.label_handle, 'Color', [0 0 0], 'FontWeight', 'bold', ...
                    'FontSize', obj.label_fontsize + 3);
            else
                % Finalize edit
                ev = obj.event_list(obj.current_object_ind);
                set(ev.label_handle, 'Color', 'k', 'FontWeight', 'normal', ...
                    'FontSize', obj.label_fontsize);
                
                editor = obj.current_object;
                if isa(editor, 'DateTimeRectangle')
                    p = editor.getPosition();
                    new_pos = [obj.dt2pos(p.x) p.y days(p.width) p.height];
                    set(ev.obj_handle, 'Position', new_pos);
                elseif isa(editor, 'DateTimeLine')
                    p = editor.getPosition();
                    new_x = obj.dt2pos(p.x1);
                    set(ev.obj_handle, 'XData', [new_x new_x]);
                end
                
                delete(editor);
                set(ev.obj_handle, 'Visible', 'on');
                
                obj.current_object = [];
                obj.current_object_ind = [];
                obj.selected_ind = [];
            end
            
            set(gcf, 'Pointer', 'arrow');
        end

        %-----------------------------------------------------------
        % CLICK COLLECTION ROUTINE
        %-----------------------------------------------------------
        function pos = get_clicks(obj, num_clicks)
            % get_clicks - Collect specified number of mouse clicks
            %
            % Output:
            %   pos - num_clicks×2 cell array: {x, y} per click
            %         x is datetime if axis is datetime, otherwise numeric
            
            pos = cell(num_clicks, 2);
            obj.adding_points = true;
            obj.num_clicks = 0;
            set(obj.main_fig, 'Pointer', 'crosshair');
            
            for ii = 1:num_clicks
                uiwait(obj.main_fig);
                cp = obj.mouse_point;
                pos{ii,1} = cp(1);
                pos{ii,2} = cp(2);
            end
            
            set(obj.main_fig, 'Pointer', 'arrow');
            obj.adding_points = false;
        end

        %-----------------------------------------------------------
        % DATETIME CONVERSION HELPERS
        %-----------------------------------------------------------
        function dt = pos2dt(obj, x)
            % Convert numeric position to datetime (if axis is datetime)
            if isdatetime(obj.main_ax.XLim(1))
                xl = obj.xbounds;
                t0 = xl(1) - timeofday(xl(1));
                dn0 = days(t0 - datetime(0,1,0));
                dt = datetime(dn0 + x, 'ConvertFrom', 'datenum');
            else
                dt = x;
            end
        end

        function x = dt2pos(obj, dt)
            % Convert datetime to numeric position (if axis is datetime)
            if isdatetime(obj.main_ax.XLim(1))
                xl = obj.xbounds;
                t0 = xl(1) - timeofday(xl(1));
                dn0 = days(t0 - datetime(0,1,0));
                x = days(dt - datetime(0,1,0)) - dn0;
            else
                x = dt;
            end
        end

        %-----------------------------------------------------------
        % LABEL FOLLOWING DURING EDIT
        %-----------------------------------------------------------
        function label_follow(obj, label_handle, editor)
            % Keep label centered on moving editor object
            if isprop(editor, 'LineObj')
                xpos = editor.Position.x1;
                if isdatetime(xpos)
                    xpos = obj.dt2pos(xpos);
                end
                label_handle.Position(1) = xpos;
            else
                verts = editor.Patch.Vertices(:,1);
                label_handle.Position(1) = mean([min(verts) max(verts)]);
            end
        end

        %-----------------------------------------------------------
        % CLEANUP ON DELETE
        %-----------------------------------------------------------
        function delete(obj)
            if ~isempty(obj.clickTimer) && isvalid(obj.clickTimer)
                stop(obj.clickTimer);
                delete(obj.clickTimer);
            end
        end
    end
end