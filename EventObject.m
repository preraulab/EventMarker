classdef EventObject
    %EVENTOBJECT  Type definition and runtime record for a single EventMarker event
    %
    %   Usage:
    %       type_obj = EventObject(name, type_ID, region, constrain)
    %
    %   Inputs:
    %       name      : char - label for the event type -- required
    %       type_ID   : integer - unique identifier for the event type -- required
    %       region    : logical - true for rectangular region, false for point/line (default: false)
    %       constrain : logical - if region, span full height when true (default: true)
    %
    %   Outputs:
    %       type_obj : EventObject - new event type/instance record
    %
    %   Notes:
    %       Used internally by EventMarker to organize event types and placed
    %       instances. Public properties: name, type_ID, region, constrain,
    %       event_ID, obj_handle, label_handle, isEditable.
    %       Public methods: EventObject (constructor), time_bounds.
    %
    %   See also: EventMarker, DateTimeLine, DateTimeRectangle
    %
    %   ∿∿∿  Prerau Laboratory MATLAB Codebase · sleepEEG.org  ∿∿∿

    %************************************************************
    % PROPERTIES
    %************************************************************
    properties (Access = public)
        name            % Display name of the event type
        type_ID         % Unique integer identifier for the event type
        region          % Logical: true for region events, false for point events
        event_ID        % Unique string ID for each placed instance (UUID)
        constrain       % Logical: vertically constrain regions to axis limits
        obj_handle = [] % Graphics handle of the placed event
        label_handle = [] % Handle to the text label
        isEditable = true % Allows an object to be edited
    end

    %%%%%%%%%%%%%%% PUBLIC METHODS %%%%%%%%%%%%%%%%%%%%%%
    methods (Access = public)

        %***********************************************
        % CONSTRUCTOR
        %***********************************************
        function obj = EventObject(varargin)
            % EventObject constructor
            %
            % Creates a new event type definition or instance.
            %
            % Inputs:
            %   name      - String name/label
            %   type_ID   - Integer type identifier (must be integer)
            %   region    - Logical indicating region event (default: false)
            %   constrain - Logical for vertical constraint of regions (default: true)

            % Generate unique instance ID using UUID
            unique_str = randi(intmax);

            % Default arguments
            args = {['object_' unique_str], unique_str, false, true, true};
            args(1:numel(varargin)) = varargin;
            [obj.name, obj.type_ID, obj.region, obj.constrain, obj.isEditable] = args{:};

            % Validate type_ID is integer
            assert(floor(obj.type_ID) == obj.type_ID, ...
                'EventObject: type_ID must be an integer');

            % Assign unique instance ID
            obj.event_ID = unique_str;
        end

        %-----------------------------------------------------------
        % TIME BOUNDS
        %-----------------------------------------------------------
        function object_bounds = time_bounds(obj)
            % time_bounds - Return the time span of the placed event
            %
            % For region events (DateTimeRectangle or rectangle):
            %   returns [t_start t_end]
            %
            % For point events (DateTimeLine or vertical line):
            %   returns single time t
            %
            % Returns [] if graphics handle is missing or invalid.

            object_bounds = [];

            if isempty(obj.obj_handle) || ~isvalid(obj.obj_handle)
                return;
            end

            h = obj.obj_handle;

            try
                if obj.region
                    %--------------------------------------------------
                    % Region case (rectangle)
                    %--------------------------------------------------
                    if isprop(h, 'Position')
                        pos = h.Position;
                        if isstruct(pos) && isfield(pos, 'x') && isfield(pos, 'width')
                            % DateTimeRectangle struct format
                            left  = pos.x;
                            right = pos.x + pos.width;
                        else
                            % Numeric rectangle [x y w h]
                            left  = pos(1);
                            right = pos(1) + pos(3);
                        end
                        object_bounds = [left right];
                    end
                else
                    %--------------------------------------------------
                    % Point case (vertical line)
                    %--------------------------------------------------
                    if isprop(h, 'XData')
                        % Standard line object
                        x = h.XData;
                        if numel(x) >= 1
                            object_bounds = x(1);
                        end
                    elseif isprop(h, 'Position')
                        % Fallback for DateTimeLine struct
                        pos = h.Position;
                        if isstruct(pos) && isfield(pos, 'x1')
                            object_bounds = pos.x1;
                        elseif isnumeric(pos)
                            object_bounds = pos(1);
                        end
                    end
                end
            catch
                object_bounds = [];
            end
        end
    end
end