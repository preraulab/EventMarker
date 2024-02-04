classdef AnnotationObject < EventObject
% AnnotationObject - A class representing an annotation object for use with
% EventMarker. Extends EvenObject
%
%   Usage:
%       obj = AnnotationObject(name, type_ID, region, constrain)
%
%   Properties (Access = public):
%       name: Text name of the event type
%       type_ID: Event type ID
%       region: Boolean indicating if it's a region (default: false)
%       event_ID: Unique event ID
%       constrain: If a region, allows for vertical constraint (default: true)
%       obj_handle: Handle to the graphical object representing the event
%       label_handle: Handle to the text label associated with the event
%
%   Methods (Access = public):
%       AnnotationObject: Constructor for creating an EventObject
%       time_bounds: Get the time bounds of the event object
%
% Example:
%   see basic_viewer.m
%
% Copyright 2024 Michael J. Prerau Laboratory. - http://www.sleepEEG.org
% ********************************************************************    

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