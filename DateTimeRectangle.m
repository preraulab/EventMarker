classdef DateTimeRectangle < handle
%DATETIMERECTANGLE  Interactive draggable and resizable rectangle with datetime support
%
%   Usage:
%       rect = DateTimeRectangle(ax, pos, callback)
%       rect = DateTimeRectangle(ax, pos, callback, 'Name', Value, ...)
%
%   Inputs:
%       ax       : axes handle - target axes -- required
%       pos      : struct with fields x (datetime/double), y (double),
%                  width (duration/double), height (double) -- required
%       callback : function handle - called with updated pos on every change -- required
%
%   Name-Value Pairs:
%       'LineColor'       : 1x3 double - RGB border color (default: [0 0.4 1])
%       'LineWidth'       : double - border width (default: 2)
%       'FaceAlpha'       : double - patch transparency (default: 0.2)
%       'HandleSize'      : double - marker size for resize handles (default: 10)
%       'ConstraintFcn'   : function handle - custom constraint @(pos)pos (default: [])
%       'ConstrainToAxis' : logical - keep rectangle inside axis limits (default: true)
%       'FullHeight'      : logical - force rectangle to span full y-limits (default: false)
%       'FullWidth'       : logical - force rectangle to span full x-limits (default: false)
%
%   Outputs:
%       rect : DateTimeRectangle handle object
%
%   Notes:
%       Supports dragging (inside), corner resizing, edge resizing, datetime-
%       safe hit testing, and automatic cursor updates. Observable properties
%       repaint the graphics on assignment. All listeners and callbacks are
%       cleaned up on deletion.
%
%   Example:
%       ax = axes;
%       plot(ax, datetime(2023,1,1)+days(0:100), rand(1,101));
%       pos.x = datetime(2023,1,10); pos.y = 0.2;
%       pos.width = days(20); pos.height = 0.5;
%       rect = DateTimeRectangle(ax, pos, @(p)disp(p));
%
%   See also: DateTimeLine, EventMarker
%
%   ∿∿∿  Prerau Laboratory MATLAB Codebase · sleepEEG.org  ∿∿∿

    %% ======================== PUBLIC PROPERTIES ========================
    properties (Access = public)
        Ax
        Patch
        Handles           % 8 resize handles
        Position          % struct: x, y, width, height
        UserCallback      % function handle
        ConstraintFcn     % function handle
    end

    %% ===================== OBSERVABLE PROPERTIES ========================
    properties (SetObservable = true)
        LineColor  = [0 0.4 1]
        LineWidth  = 2
        FaceAlpha  = 0.2
        HandleSize = 10
    end

    %% ======================== PRIVATE PROPERTIES ========================
    properties (Access = private)
        ActiveHandle
        DragStartPos
        DragStartPoint
        IsDragging = false
        IsDateTimeX = false
        PropListeners = []
    end

    %% ============================ METHODS ===============================
    methods (Access = public)
        function obj = DateTimeRectangle(ax, pos, callback, varargin)
            % Constructor

            p = inputParser;
            addParameter(p, 'LineColor', obj.LineColor);
            addParameter(p, 'LineWidth', obj.LineWidth);
            addParameter(p, 'FaceAlpha', obj.FaceAlpha);
            addParameter(p, 'HandleSize', obj.HandleSize);
            addParameter(p, 'ConstraintFcn', []);
            addParameter(p, 'ConstrainToAxis', true);
            addParameter(p, 'FullHeight', false);
            addParameter(p, 'FullWidth', false);
            parse(p, varargin{:});

            obj.Ax = ax;
            obj.Position = pos;
            obj.UserCallback = callback;
            obj.LineColor  = p.Results.LineColor;
            obj.LineWidth  = p.Results.LineWidth;
            obj.FaceAlpha  = p.Results.FaceAlpha;
            obj.HandleSize = p.Results.HandleSize;

            obj.IsDateTimeX = isa(pos.x,'datetime');

            if ~isempty(p.Results.ConstraintFcn)
                obj.ConstraintFcn = p.Results.ConstraintFcn;
            elseif p.Results.ConstrainToAxis || p.Results.FullHeight || p.Results.FullWidth
                obj.ConstraintFcn = obj.makeDefaultConstraint(...
                    p.Results.ConstrainToAxis, ...
                    p.Results.FullHeight, ...
                    p.Results.FullWidth);
            end

            if ~isempty(obj.ConstraintFcn)
                obj.Position = obj.ConstraintFcn(obj.Position);
            end

            obj.createPatch();
            obj.createHandles();
            obj.updateGraphics();
            obj.attachPropertyListeners();

            fig = ancestor(ax,'figure');
            fig.WindowButtonMotionFcn = @(~,~)obj.onMouseMove();
            fig.WindowButtonUpFcn     = @(~,~)obj.onMouseUp();
        end

        function delete(obj)
            % Destructor: clean up listeners and graphics
            if ~isempty(obj.PropListeners)
                delete(obj.PropListeners);
            end
            if ~isempty(obj.Patch) && isvalid(obj.Patch)
                delete(obj.Patch);
            end
            if ~isempty(obj.Handles)
                delete(obj.Handles(isvalid(obj.Handles)));
            end
            if ~isempty(obj.Ax) && isvalid(obj.Ax)
                fig = ancestor(obj.Ax,'figure');
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

        function setPosition(obj,pos)
            obj.Position = pos;
            obj.updateGraphics();
            obj.fireCallback();
        end

        function pos = getPosition(obj)
            pos = obj.Position;
        end

        function fcn = makeDefaultConstraint(obj, constrainToAxis, fullHeight, fullWidth)
            fcn = @(pos)obj.applyDefaultConstraint(pos, constrainToAxis, fullHeight, fullWidth);
        end
    end

    %% ========================== PRIVATE METHODS =========================
    methods (Access = private)
        function attachPropertyListeners(obj)
            obj.PropListeners = [ ...
                addlistener(obj,'LineColor','PostSet',@(~,~)obj.onLineColorChanged())
                addlistener(obj,'LineWidth','PostSet',@(~,~)obj.onLineWidthChanged())
                addlistener(obj,'FaceAlpha','PostSet',@(~,~)obj.onFaceAlphaChanged())
                addlistener(obj,'HandleSize','PostSet',@(~,~)obj.onHandleSizeChanged()) ];
        end

        function onLineColorChanged(obj)
            if isempty(obj.Patch) || ~isvalid(obj.Patch); return; end
            obj.Patch.EdgeColor = obj.LineColor;
            obj.Patch.FaceColor = obj.LineColor;
            for k=1:numel(obj.Handles)
                if isvalid(obj.Handles(k))
                    obj.Handles(k).MarkerFaceColor = obj.LineColor;
                end
            end
        end

        function onLineWidthChanged(obj)
            if isvalid(obj.Patch)
                obj.Patch.LineWidth = obj.LineWidth;
            end
        end

        function onFaceAlphaChanged(obj)
            if isvalid(obj.Patch)
                obj.Patch.FaceAlpha = obj.FaceAlpha;
            end
        end

        function onHandleSizeChanged(obj)
            for k=1:numel(obj.Handles)
                if isvalid(obj.Handles(k))
                    obj.Handles(k).MarkerSize = obj.HandleSize;
                end
            end
        end

        % ------------------- Geometry and Graphics -------------------
        function [xv,yv] = getVertices(obj)
            x = obj.Position.x;
            y = obj.Position.y;
            w = obj.Position.width;
            h = obj.Position.height;
            xv = [x x+w x+w x x];
            yv = [y y y+h y+h y];
        end

        function createPatch(obj)
            [xv,yv] = obj.getVertices();
            obj.Patch = patch(obj.Ax, xv, yv, obj.LineColor, ...
                'FaceAlpha',obj.FaceAlpha, ...
                'EdgeColor',obj.LineColor, ...
                'LineWidth',obj.LineWidth, ...
                'ButtonDownFcn',@(~,~)obj.startDrag());
        end

        function createHandles(obj)
            obj.Handles = gobjects(8,1);
            for i=1:8
                obj.Handles(i) = line(obj.Ax,0,0,'Marker','s', ...
                    'MarkerSize',obj.HandleSize, ...
                    'MarkerFaceColor',obj.LineColor, ...
                    'MarkerEdgeColor','k', ...
                    'ButtonDownFcn',@(~,~)obj.startResize(i));
            end
        end

        function updateGraphics(obj)
            [xv,yv] = obj.getVertices();
            obj.Patch.XData = xv;
            obj.Patch.YData = yv;

            % corners
            for i=1:4
                obj.Handles(i).XData = xv(i);
                obj.Handles(i).YData = yv(i);
            end
            % sides
            obj.Handles(5).XData = mean(xv(1:2)); obj.Handles(5).YData = yv(1);
            obj.Handles(6).XData = xv(2);         obj.Handles(6).YData = mean(yv(2:3));
            obj.Handles(7).XData = mean(xv(3:4)); obj.Handles(7).YData = yv(3);
            obj.Handles(8).XData = xv(1);         obj.Handles(8).YData = mean(yv([1 4]));
        end

        % ------------------- Interaction Logic -------------------
        function startDrag(obj)
            obj.IsDragging = true;
            obj.ActiveHandle = 0;
            obj.DragStartPoint = obj.getCurrentPoint();
            obj.DragStartPos = obj.Position;
            obj.updateCursor('move');
        end

        function startResize(obj,idx)
            obj.IsDragging = true;
            obj.ActiveHandle = idx;
            obj.DragStartPoint = obj.getCurrentPoint();
            obj.DragStartPos = obj.Position;
        end

        function onMouseMove(obj)
            cp = obj.getCurrentPoint();
            if ~obj.IsDragging
                idx = obj.hitTest(cp);
                if isnan(idx), obj.updateCursor('arrow'); return; end
                if idx==0, obj.updateCursor('move'); return; end
                if idx<=4, obj.updateCursor('corner',idx); else, obj.updateCursor('side',idx); end
                return
            end

            dpX = cp(1) - obj.DragStartPoint(1);
            dpY = cp(2) - obj.DragStartPoint(2);
            pos0 = obj.DragStartPos;
            newPos = pos0;

            dx = obj.IsDateTimeX * days(dpX) + ~obj.IsDateTimeX * dpX;

            switch obj.ActiveHandle
                case 0
                    newPos.x = pos0.x + dx;
                    newPos.y = pos0.y + dpY;
                case 1
                    newPos.x = pos0.x + dx; newPos.y = pos0.y + dpY;
                    newPos.width = pos0.width - dx; newPos.height = pos0.height - dpY;
                case 2
                    newPos.y = pos0.y + dpY;
                    newPos.width = pos0.width + dx; newPos.height = pos0.height - dpY;
                case 3
                    newPos.width = pos0.width + dx; newPos.height = pos0.height + dpY;
                case 4
                    newPos.x = pos0.x + dx;
                    newPos.width = pos0.width - dx; newPos.height = pos0.height + dpY;
                case 5
                    newPos.y = pos0.y + dpY; newPos.height = pos0.height - dpY;
                case 6
                    newPos.width = pos0.width + dx;
                case 7
                    newPos.height = pos0.height + dpY;
                case 8
                    newPos.x = pos0.x + dx; newPos.width = pos0.width - dx;
            end

            if ~isempty(obj.ConstraintFcn)
                newPos = obj.ConstraintFcn(newPos);
            end

            obj.Position = newPos;
            obj.updateGraphics();
            obj.fireCallback();
        end

        function onMouseUp(obj)
            obj.IsDragging = false;
            obj.ActiveHandle = [];
            obj.updateCursor('arrow');
        end

        function pt = getCurrentPoint(obj)
            pt = obj.Ax.CurrentPoint(1,1:2);
        end

        function fireCallback(obj)
            if ~isempty(obj.UserCallback)
                obj.UserCallback(obj.Position);
            end
        end

        % ------------------- Hit Testing & Cursor -------------------
        function idx = hitTest(obj,cp)
            [xv,yv] = obj.getVertices();
            xv = datenum(xv); cpX = datenum(cp(1)); cpY = cp(2);
            tolX = 0.02*range(datenum(obj.Ax.XLim));
            tolY = 0.02*range(obj.Ax.YLim);

            for i=1:4
                if abs(cpX-xv(i))<tolX && abs(cpY-yv(i))<tolY, idx=i; return; end
            end
            for i=5:8
                hx = datenum(obj.Handles(i).XData);
                hy = obj.Handles(i).YData;
                if abs(cpX-hx)<tolX && abs(cpY-hy)<tolY, idx=i; return; end
            end

            if cpX>=min(xv) && cpX<=max(xv) && cpY>=min(yv) && cpY<=max(yv)
                idx = 0;
            else
                idx = NaN;
            end
        end

        function updateCursor(obj,type,idx)
            if nargin<3, idx=obj.ActiveHandle; end
            fig = ancestor(obj.Ax,'figure');
            switch type
                case 'move',   fig.Pointer='fleur';
                case 'corner', fig.Pointer='fleur';
                case 'side',   fig.Pointer='fleur';
                otherwise,     fig.Pointer='arrow';
            end
        end

        % ------------------- Utilities -------------------
        function pos = applyDefaultConstraint(obj,pos,constrainToAxis,fullHeight,fullWidth)
            if ~constrainToAxis, return; end
            xLim = obj.Ax.XLim; yLim = obj.Ax.YLim;
            if fullHeight
                pos.y = yLim(1); pos.height = diff(yLim);
            end
            if fullWidth
                pos.x = xLim(1); pos.width = diff(xLim);
            end
        end

        function tf = callbackBelongsToObj(obj,cb)
            tf = false;
            if ~isa(cb,'function_handle'), return; end
            finfo = functions(cb);
            if isfield(finfo,'workspace') && ~isempty(finfo.workspace)
                ws = finfo.workspace;
                if iscell(ws), ws = [ws{:}]; end
                for k=1:numel(ws)
                    if any(structfun(@(v)isequal(v,obj),ws(k)))
                        tf = true; return;
                    end
                end
            end
        end
    end
end
