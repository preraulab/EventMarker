function em = basic_viewer()
ccc

%Create figure
f=figure('color','w','visible','off');
ax=figdesign(2,1,'margins',[.05,.1,.05,.05,.05]);

%Plot image (spectrogram)
subplot(ax(1))
imagesc(peaks(1000));
axis xy
xbounds=[0 1000];
ybounds=[0 1000];

%Plot time domain
subplot(ax(2))
plot(randn(1,1000));

%Call event marker class to mark on the image
% obj=EventMarker(<axis>,<xbounds>,<ybounds>
em=EventMarker(ax(1),xbounds, ybounds);

%Add the main and label axes to the axis vector
ax=[ax em.main_ax, em.label_ax];

%Add events
%obj.add_event_type(EventObject(<event type name>, <event ID>, <region? vs. point>, <bounded to yaxis?>)
em.add_event_type(EventObject('REM',10,true,true));
em.add_event_type(EventObject('Eyes Closed',3,false));
em.add_event_type(EventObject('Alpha',5,true,false));
em.add_event_type(EventObject('Arousal',4,false,false));

%Scroll axes
scrollzoompan(ax(1));

set(f,'KeyPressFcn',@(src,event)handle_keys(event,em),'units','normalized','position',[0 0 1 1],'visible','on');
linkaxes(ax,'x');

%Make menu item to put in fixed time scale
m=uimenu('Label','Markers');
%Change the time scale
uimenu(m,'Label','Save Events...','callback',@(src,evnt)em.save,'accelerator','s');
uimenu(m,'Label','Load Events...','callback',@(src,evnt)em.load,'accelerator','s');

%************************************************************
%                      HANDLE HOTKEYS
%************************************************************
function handle_keys(event, em)

switch event.Key
    case {'backspace','delete'}
        em.delete_selected;
end

%Check for hotkeys pressed
switch lower(event.Character)
    case '1'
        em.mark_event(10);
    case '2'
        em.mark_event(3);
    case '3'
        em.mark_event(5);
    case '4'
        em.mark_event(4);
        
end

