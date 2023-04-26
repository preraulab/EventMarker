function EEG_marked_viewer(data, Fs, frequency_range, taper_params, window_params, min_NFFT, detrend_opt, plot_on, verbose)

if nargin==0
    Fs=200;
    N = Fs*60*30;
    data=randn(1,N);
    frequency_range = [];
    taper_params = [];
    window_params = [];
    min_NFFT = [];
    detrend_opt = [];
    plot_on = false;
    verbose = true;
end

[spect, stimes, sfreqs]=multitaper_spectrogram_mex(data, Fs, frequency_range, taper_params, window_params, min_NFFT, detrend_opt, [], plot_on, verbose);
t=(1:length(data))/Fs;

%Create figure
f=figure('color','w','visible','off');
ax=figdesign(2,1,'margins',[.05,.1,.05,.05,.05]);

%Plot image (spectrogram)
subplot(ax(1))
imagesc(stimes,sfreqs,pow2db(spect));
axis xy
xbounds=stimes([1 end]);
ybounds=sfreqs([1 end]);

%Plot time domain
subplot(ax(2))
plot(t,data);

%Call event marker class to mark on the image
em=EventMarker(ax(1),xbounds, ybounds, [], [], [], [], @test);


%Add events
%obj.add_event_type(EventObject(<event type name>, <event ID>, <region? vs. point>, <bounded to yaxis?>)
em.add_event_type(EventObject('REM',1,true,true));
em.add_event_type(EventObject('Eyes Closed',2,false));
em.add_event_type(EventObject('Alpha',3,true,false));
em.add_event_type(EventObject('Arousal',4,false,false));

%Add the main and label axes to the axis vector
ax=[ax em.main_ax, em.label_ax];
linkaxes(ax,'x');
%Scroll axes
scrollzoompan(ax);

set(f,'KeyPressFcn',@(src,event)handle_keys(event,em),'units','normalized','position',[0 0 1 1],'visible','on');

%Make menu item to put in fixed time scale
m=uimenu('Label','Markers');
%Change the time scale
uimenu(m,'Label','Save Events...','callback',@(src,evnt)em.save,'accelerator','s');
uimenu(m,'Label','Load Events...','callback',@(src,evnt)em.load,'accelerator','s');


function test(varargin)
disp(varargin);



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
    case 'r'
        em.mark_event(1);
    case 'a'
        em.mark_event(3);
    case 'e'
        em.mark_event(2);
    case 'o'
        em.mark_event(4);
    case ' '
        prompt = {'Enter annotation text:','Enter annotation time:'};
        dlgtitle = 'Annotation Input';
        dims = [1 40];
        definput = {' ','0'};
        answer = inputdlg(prompt,dlgtitle,dims,definput);

        em.add_annotation(answer{1}, str2double(answer{2}));

end

