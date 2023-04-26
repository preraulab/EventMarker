classdef AnnotationObject < EventObject
    
    %%%%%%%%%%%%%%%% public properties %%%%%%%%%%%%%%%%%%
    properties (Access = public)
        
    end
    
    %%%%%%%%%%%%%%% protected methods %%%%%%%%%%%%%%%%%%%%%%
    methods (Access = public)
        
        %***********************************************
        %             CONSTRUCTOR METHOD
        %***********************************************
        
        function obj=AnnotationObject(text)
            %Set up default param values
            new_id=round(now);
            
            if nargin > 0
                obj.name = text;
            else
                obj.name = ['Annot_' num2str(new_id)];
            end

            obj.region = false;
            obj.constrain = true;
            obj.type_ID = -99;
            obj.event_ID = new_id;
        end
    end
end