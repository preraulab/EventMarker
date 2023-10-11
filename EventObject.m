classdef EventObject

    %%%%%%%%%%%%%%%% public properties %%%%%%%%%%%%%%%%%%
    properties (Access = public)
        name %Text name of event type
        type_ID %Event type ID
        region %Boolean for being a region
        event_ID %Unique event ID

        %If a region, this allows for vertical constraint
        constrain

        obj_handle=[]
        label_handle=[]
    end

    %%%%%%%%%%%%%%% protected methods %%%%%%%%%%%%%%%%%%%%%%
    methods (Access = public)

        %***********************************************
        %             CONSTRUCTOR METHOD
        %***********************************************

        function obj=EventObject(varargin)
            %Set up default param values

            %Create a "unique" id
            new_id=randi(100000000);

            args={['object_' num2str(new_id) ], new_id, false, true};
            args(1:length(varargin))=varargin;
            [obj.name, obj.type_ID, obj.region, obj.constrain]=args{:};

            assert(floor(obj.type_ID) == obj.type_ID, 'Object type ID must be an integer')
        end

        function object_bounds = time_bounds(obj)
            %Handle region and line separately
            if obj.region
                %Get the xpositions
                event_pos=get(obj.obj_handle,'position');

                %Get the region left bound
                object_bounds= [ event_pos(1), event_pos(1)+event_pos(3)];
            else
                %Get the xpositions
                event_pos=get(obj.obj_handle,'xdata');
                %Get the x-value of the vertical line
                object_bounds=event_pos(1);
            end
        end
    end
end