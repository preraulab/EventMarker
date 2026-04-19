classdef DateTimeLine < handle
    %DATETIMELINE  Interactive draggable line segment supporting datetime axes
    %
    %   Usage:
    %       ln = DateTimeLine(ax, pos, callback)
    %       ln = DateTimeLine(ax, pos, callback, 'Name', Value, ...)
    %
    %   Inputs:
    %       ax       : axes handle - target axes -- required
    %       pos      : struct with fields x1, y1, x2, y2 (datetime or double) -- required
    %       callback : function handle - called after every position change -- required
    %
    %   Outputs:
    %       ln : DateTimeLine handle object
    %
    %   Notes:
    %       Supports numeric and datetime x-axes. Two endpoint handles allow
    %       precise positioning; dragging the line body moves both together.
    %       Observable appearance properties (LineColor, LineWidth, HandleSize)
    %       update the graphics automatically when modified.
    %
    %   Example:
    %       ax = axes;
    %       plot(ax, datetime(2023,1,1)+days(0:100), rand(1,101));
    %       pos.x1 = datetime(2023,1,10); pos.y1 = 0.2;
    %       pos.x2 = datetime(2023,1,30); pos.y2 = 0.8;
    %       ln = DateTimeLine(ax, pos, @(p)disp(p));
    %
    %   See also: DateTimeRectangle, EventMarker
    %
    %   ∿∿∿  Prerau Laboratory MATLAB Codebase · sleepEEG.org  ∿∿∿

    %************************************************************
    % PROPERTIES
    %************************************************************
    properties (Access = public)
        Ax              % Axes handle containing the line
        LineObj         % Handle to the main line graphics object
        Handles         % 2x1 array of endpoint handle line objects
        Position        % Struct with fields: x1, y1, x2, y2
        UserCallback    % Function handle called after every position change
        ConstraintFcn   % Optional function handle to constrain position
    end

    properties (SetObservable = true)
        LineColor = [0 0.4 1]   % Color of line and endpoint handles [R G B]
        LineWidth = 2           % Width of the line
        HandleSize = 10         % Marker size of endpoint handles
    end

    properties (Access = private)
        ActiveHandle = []       % Active handle: 0 = whole line drag, 1 or 2 = endpoint
        DragStartPos            % Position struct at start of drag
        DragStartPoint          % Cursor position [x y] at start of drag
        IsDragging = false      % Flag indicating active drag operation
        IsDateTimeX = false     % True if x-axis uses datetime ruler
        PropListeners = []      % Array of property listeners for appearance updates
    end

    %%%%%%%%%%%%%%% PUBLIC METHODS %%%%%%%%%%%%%%%%%%%%%%
    methods (Access = public)

        %***********************************************
        % CONSTRUCTOR
        %***********************************************
        function obj = DateTimeLine(ax, pos, callback, varargin)
            % DateTimeLine constructor
            %
            % Creates an interactive draggable line segment on the specified axes.
            % Supports datetime or numeric x-axes. Installs figure mouse callbacks for interaction.
            %
            % Inputs:
            %   ax       - Axes handle on which to draw the line
            %   pos      - Struct with fields x1, y1, x2, y2
            %              (x1/x2 may be datetime if axis is datetime)
            %   callback - Function handle called whenever position changes:
            %              callback(current_pos_struct)
            %
            % Name-Value Pairs:
            %   LineColor          - [R G B] color of line and handles
            %   LineWidth          - Width of the line
            %   HandleSize         - Size of endpoint handle markers
            %   ConstraintFcn      - Custom function handle to constrain position
            %   ConstrainToAxis    - Logical; clamp endpoints within axis limits
            %   FullHeight         - Logical; force line to span full axis height
            %   FullWidth          - Logical; force line to span full axis width
            %   ConstrainHorizontal- Logical; force horizontal line (y1 = y2)
            %   ConstrainVertical  - Logical; force vertical line (x1 = x2)

            p = inputParser;
            addParameter(p, 'LineColor',          obj.LineColor);
            addParameter(p, 'LineWidth',          obj.LineWidth);
            addParameter(p, 'HandleSize',         obj.HandleSize);
            addParameter(p, 'ConstraintFcn',      []);
            addParameter(p, 'ConstrainToAxis',    true);
            addParameter(p, 'FullHeight',         false);
            addParameter(p, 'FullWidth',          false);
            addParameter(p, 'ConstrainHorizontal',false);
            addParameter(p, 'ConstrainVertical',  false);
            parse(p, varargin{:});

            obj.Ax            = ax;
            obj.Position      = pos;
            obj.UserCallback  = callback;
            obj.IsDateTimeX   = isa(pos.x1, 'datetime');

            obj.LineColor = p.Results.LineColor;
            obj.LineWidth = p.Results.LineWidth;
            obj.HandleSize = p.Results.HandleSize;

            if ~isempty(p.Results.ConstraintFcn)
                obj.ConstraintFcn = p.Results.ConstraintFcn;
            elseif any([p.Results.ConstrainToAxis, p.Results.FullHeight, ...
                        p.Results.FullWidth, p.Results.ConstrainHorizontal, ...
                        p.Results.ConstrainVertical])
                obj.ConstraintFcn = obj.makeDefaultConstraint(...
                    p.Results.ConstrainToAxis, ...
                    p.Results.FullHeight, ...
                    p.Results.FullWidth, ...
                    p.Results.ConstrainHorizontal, ...
                    p.Results.ConstrainVertical);
            end

            if ~isempty(obj.ConstraintFcn)
                obj.Position = obj.ConstraintFcn(obj.Position);
            end

            obj.createLine();
            obj.createHandles();
            obj.updateGraphics();
            obj.attachPropertyListeners();

            fig = ancestor(ax, 'figure');
            fig.WindowButtonMotionFcn = @(~,~) obj.onMouseMove();
            fig.WindowButtonUpFcn     = @(~,~) obj.onMouseUp();
        end

        %-----------------------------------------------------------
        % DESTRUCTOR
        %-----------------------------------------------------------
        function delete(obj)
            % delete - Clean up graphics, listeners, and callbacks
            %
            % Removes all created graphics objects, property listeners,
            % and clears figure mouse callbacks installed by this instance.

            if ~isempty(obj.PropListeners)
                delete(obj.PropListeners);
            end

            if ~isempty(obj.LineObj) && isvalid(obj.LineObj)
                delete(obj.LineObj);
            end

            if ~isempty(obj.Handles)
                delete(obj.Handles(isvalid(obj.Handles)));
            end

            if ~isempty(obj.Ax) && isvalid(obj.Ax)
                fig = ancestor(obj.Ax, 'figure');
                if isvalid(fig)
                    if obj.callbackBelongsToObj(fig.WindowButtonMotionFcn)
                        fig.WindowButtonMotionFcn = '';
                    end
                    if obj.callbackBelongsToObj(fig.WindowButtonUpFcn)
                        fig.WindowButtonUpFcn = '';
                    end
                end
            end
        end

        %-----------------------------------------------------------
        % SET POSITION
        %-----------------------------------------------------------
        function setPosition(obj, pos)
            % setPosition - Programmatically update line position
            %
            % Applies constraint (if any), refreshes graphics, and fires user callback.

            if ~isempty(obj.ConstraintFcn)
                pos = obj.ConstraintFcn(pos);
            end
            obj.Position = pos;
            obj.updateGraphics();
            obj.fireCallback();
        end

        %-----------------------------------------------------------
        % GET POSITION
        %-----------------------------------------------------------
        function pos = getPosition(obj)
            % getPosition - Retrieve current position struct
            pos = obj.Position;
        end

        %-----------------------------------------------------------
        % SET CONSTRAINT FUNCTION
        %-----------------------------------------------------------
        function setConstraintFcn(obj, fcn)
            % setConstraintFcn - Replace the current constraint function
            obj.ConstraintFcn = fcn;
        end

        %-----------------------------------------------------------
        % MAKE DEFAULT CONSTRAINT
        %-----------------------------------------------------------
        function f = makeDefaultConstraint(obj, constrainToAxis, fullHeight, fullWidth, horiz, vert)
            % makeDefaultConstraint - Generate built-in constraint function
            f = @(pos) obj.applyDefaultConstraint(pos, constrainToAxis, fullHeight, fullWidth, horiz, vert);
        end
    end

    %%%%%%%%%%%%%%% PRIVATE METHODS %%%%%%%%%%%%%%%%%%%%%%
    methods (Access = private)

        %-----------------------------------------------------------
        % ATTACH PROPERTY LISTENERS
        %-----------------------------------------------------------
        function attachPropertyListeners(obj)
            % attachPropertyListeners - Monitor appearance properties for automatic updates
            obj.PropListeners = [ ...
                addlistener(obj, 'LineColor',  'PostSet', @(~,~) obj.onLineColorChanged()); ...
                addlistener(obj, 'LineWidth',  'PostSet', @(~,~) obj.onLineWidthChanged()); ...
                addlistener(obj, 'HandleSize', 'PostSet', @(~,~) obj.onHandleSizeChanged()) ];
        end

        %-----------------------------------------------------------
        % PROPERTY CHANGE CALLBACKS
        %-----------------------------------------------------------
        function onLineColorChanged(obj)
            % onLineColorChanged - Refresh colors when LineColor is modified
            if ~isvalid(obj.LineObj), return; end
            obj.LineObj.Color = obj.LineColor;
            validHandles = obj.Handles(isvalid(obj.Handles));
            set(validHandles, 'MarkerFaceColor', obj.LineColor);
        end

        function onLineWidthChanged(obj)
            % onLineWidthChanged - Refresh line width when LineWidth is modified
            if isvalid(obj.LineObj)
                obj.LineObj.LineWidth = obj.LineWidth;
            end
        end

        function onHandleSizeChanged(obj)
            % onHandleSizeChanged - Refresh handle size when HandleSize is modified
            validHandles = obj.Handles(isvalid(obj.Handles));
            set(validHandles, 'MarkerSize', obj.HandleSize);
        end

        %-----------------------------------------------------------
        % CREATE GRAPHICS OBJECTS
        %-----------------------------------------------------------
        function createLine(obj)
            % createLine - Construct the main line graphics object
            p = obj.Position;
            obj.LineObj = line(obj.Ax, ...
                [p.x1 p.x2], [p.y1 p.y2], ...
                'Color', obj.LineColor, ...
                'LineWidth', obj.LineWidth, ...
                'HitTest', 'on', ...
                'ButtonDownFcn', @(~,~) obj.startDragLine());
        end

        function createHandles(obj)
            % createHandles - Construct two endpoint handles
            obj.Handles = gobjects(2,1);
            for i = 1:2
                obj.Handles(i) = line(obj.Ax, NaN, NaN, ...
                    'Marker', 's', ...
                    'MarkerSize', obj.HandleSize, ...
                    'MarkerFaceColor', obj.LineColor, ...
                    'MarkerEdgeColor', 'k', ...
                    'LineStyle', 'none', ...
                    'HitTest', 'on', ...
                    'ButtonDownFcn', @(~,~) obj.startDragHandle(i));
            end
        end

        %-----------------------------------------------------------
        % UPDATE GRAPHICS
        %-----------------------------------------------------------
        function updateGraphics(obj)
            % updateGraphics - Refresh line and handle positions from current Position
            p = obj.Position;
            obj.LineObj.XData = [p.x1 p.x2];
            obj.LineObj.YData = [p.y1 p.y2];
            obj.Handles(1).XData = p.x1; obj.Handles(1).YData = p.y1;
            obj.Handles(2).XData = p.x2; obj.Handles(2).YData = p.y2;
        end

        %-----------------------------------------------------------
        % INTERACTION START
        %-----------------------------------------------------------
        function startDragLine(obj)
            % startDragLine - Begin dragging the entire line
            obj.IsDragging     = true;
            obj.ActiveHandle   = 0;
            obj.DragStartPoint = obj.getCurrentPoint();
            obj.DragStartPos   = obj.Position;
        end

        function startDragHandle(obj, idx)
            % startDragHandle - Begin dragging a specific endpoint
            obj.IsDragging     = true;
            obj.ActiveHandle   = idx;
            obj.DragStartPoint = obj.getCurrentPoint();
            obj.DragStartPos   = obj.Position;
        end

        %-----------------------------------------------------------
        % MOUSE MOVE HANDLER
        %-----------------------------------------------------------
        function onMouseMove(obj)
            % onMouseMove - Process cursor movement during active drag
            if ~obj.IsDragging, return; end

            cp = obj.getCurrentPoint();
            dp = cp - obj.DragStartPoint;
            pos0 = obj.DragStartPos;

            dx = obj.IsDateTimeX * days(dp(1)) + ~obj.IsDateTimeX * dp(1);
            dy = dp(2);

            newPos = pos0;

            switch obj.ActiveHandle
                case 0  % drag whole line
                    newPos.x1 = pos0.x1 + dx; newPos.x2 = pos0.x2 + dx;
                    newPos.y1 = pos0.y1 + dy; newPos.y2 = pos0.y2 + dy;
                case 1  % first endpoint
                    newPos.x1 = pos0.x1 + dx;
                    newPos.y1 = pos0.y1 + dy;
                case 2  % second endpoint
                    newPos.x2 = pos0.x2 + dx;
                    newPos.y2 = pos0.y2 + dy;
            end

            if ~isempty(obj.ConstraintFcn)
                newPos = obj.ConstraintFcn(newPos);
            end

            obj.Position = newPos;
            obj.updateGraphics();
            obj.fireCallback();
        end

        %-----------------------------------------------------------
        % MOUSE UP HANDLER
        %-----------------------------------------------------------
        function onMouseUp(obj)
            % onMouseUp - Finalize drag operation
            obj.IsDragging   = false;
            obj.ActiveHandle = [];
        end

        %-----------------------------------------------------------
        % UTILITIES
        %-----------------------------------------------------------
        function cp = getCurrentPoint(obj)
            % getCurrentPoint - Current mouse position in axes data units
            cp = obj.Ax.CurrentPoint(1,1:2);
        end

        function fireCallback(obj)
            % fireCallback - Execute user callback with current position
            if ~isempty(obj.UserCallback)
                obj.UserCallback(obj.Position);
            end
        end

        function pos = applyDefaultConstraint(obj, pos, constrainToAxis, fullHeight, fullWidth, horiz, vert)
            % applyDefaultConstraint - Enforce built-in constraints
            xl = obj.Ax.XLim;
            yl = obj.Ax.YLim;

            if fullWidth
                pos.x1 = xl(1); pos.x2 = xl(2);
            end
            if fullHeight
                pos.y1 = yl(1); pos.y2 = yl(2);
            end
            if horiz
                pos.y2 = pos.y1;
            end
            if vert
                pos.x2 = pos.x1;
            end
            if constrainToAxis
                pos.x1 = max(min(pos.x1, xl(2)), xl(1));
                pos.x2 = max(min(pos.x2, xl(2)), xl(1));
                pos.y1 = max(min(pos.y1, yl(2)), yl(1));
                pos.y2 = max(min(pos.y2, yl(2)), yl(1));
            end
        end

        function tf = callbackBelongsToObj(obj, cb)
            % callbackBelongsToObj - Verify if callback was created by this instance
            tf = false;
            if ~isa(cb, 'function_handle')
                return;
            end
            finfo = functions(cb);
            if isfield(finfo, 'workspace') && ~isempty(finfo.workspace)
                ws = finfo.workspace;
                if iscell(ws)
                    ws = [ws{:}];
                end
                for k = 1:numel(ws)
                    if any(structfun(@(v) isequal(v, obj), ws(k)))
                        tf = true;
                        return;
                    end
                end
            end
        end
    end
end