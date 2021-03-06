function varargout = aslgui3_testSubtractDominantMotion(varargin)
% ASLGUI3 Custom user interface to generate training data for ASL recognition system.
%       ASLGUI3...
%
%   Created 4/18/12 MRE
%   Updated 4/20/12 MRE
%   Updated 10/25/12 JWA - for testing SubtractDominantMotion from CV HW#3

close all
clc
tic

%Load data file created by batchSIFT
%jvf trainDataFile='compiled data sets/trainset_jf2_1.mat' %'batchpcaall20';     %   <------------change this for diff files
%jvf load(trainDataFile,'-mat','trainingSet');

% Declare non-UI data here so that they can be used in any functions in
% this GUI file. 
global map;  %jvf2
mInputArgs          =   varargin;   % Command line arguments when invoking the GUI
mOutputArgs         =   {};         % Variable for storing output when GUI returns
mFrame              =   [];         % Sample data captured by this GUI
mFrameNumber        =   [];
mTimer              =   0;
mNet                =   [];
mPrediction         =   0;
mAreWeLoading       =   'no';
mAreWePredicting    =   'no';

% mean shift global variables
template            =   [];
image1_PDF          =   [];
x0                  =   0;
y0                  =   0;        
H                   =   0;
W                   =   0; 
Lmap                =   0;
ParzenWindow        =   [];
gx                  =   0;
gy                  =   0;
index_start         =   1;            % DO I NEED THIS ANYMORE?
f_thresh            =   0.50; % Similarity Threshold
max_it              =   15; % Number max of iterations to converge
kernel_type         =   'Gaussian'; % Parzen window parameters
radius              =   1;

mAreWeFinished      =   'no';       % Allow data processing in the background
% Variables for supporting custom property/value pairs
mPropertyDefs   =   {...        % Custom property/value pairs of this GUI
                     'videowidth',  @localValidateInput, 'mVideoWidth';
                     'videoheight', @localValidateInput, 'mVideoHeight';
                     'nnfile',     @localValidateInput, 'mFile'};
mFile =   '';         % selected neural network data file
mPath     =   fullfile(cd,'Program Home Directory\compiled data sets'); %jvf

% Video Input
% determine video type of webcam
videoInfo = imaqhwinfo('winvideo',1)
videoFormat = videoInfo.DefaultFormat

% set video format
global changeColorSpace; %if 1, fcn is called after screen capture to conver to rgb
if strcmp('YUY',videoFormat(1:3))==1%jvf2
  videoFormat = 'YUY2_640x480'; % justin's PC
  changeColorSpace=1;
elseif strcmp('MJP',videoFormat(1:3))==1
        videoFormat = 'MJPG_640x480';
        changeColorSpace=0;
else
    display('Error: Review set video format section');
    %currently setup for justin or jasons computer
    %if jasons, (mjpg) format is rgb so changes aren't required later
    %if justins, (yuy) format must be converted to rgb during screen
    %captures
end

vid = videoinput('winvideo',1,videoFormat);         %creates video input object
% vid.ReturnedColorSpace = 'grayscale';   % turns the frame from RGB to grayscale
vid.FramesPerTrigger = Inf;             % we want it to acquire frames until the camera is stopped
set(vid,'TimerPeriod',0.1);               % run the TimerFcn every 0.2 seconds
set(vid,'TimerFcn',@mem_mon);           % use a callback function to monitor memory
triggerconfig(vid,'manual');            % starts acquiring frames only on manual trigger
vidRes = get(vid,'VideoResolution');    % should be 640x480
mVideoWidth     =   vidRes(1);          % else use input property 'videowidth'
mVideoHeight    =   vidRes(2);          % else use input property 'videoheight'
nBands = get(vid,'NumberOfBands')

wid = 320;      % width of image
hei = 240;      % height of image
scl = .25;      % scaling factor (e.g. 0.5 cuts the image in half)
wbox = 0.25;  % percentage of width to keep (e.g. 0.5 means the middle half of the image is kept)
hbox = 0.25;   % percentage of height to keep

oldBoundingBox = [1,1,wid*scl,hei*scl]; % needed for first time through SubtractDominantMotion

% GUI Dimensions (units are characters, unless otherwise noted)
x.Main = 100;
y.Main = 5;
width.Main = 140;
height.Main = 38;

x.Edge = 1.6;
y.Edge = 0.4;

y.Panel.NNproperties = 7;
y.Panel.Prediction = 8.77;
x.Panel.Prediction = 40;
height.line = 0.077;
width.Button = 17.8;
height.Button = 2.38;
x.Button = 2.4;
y.Button = 0.62;

pix2char = [7 19.9604]; %a_char = a_pixels./f;

% The following dimensions are determined based on the ones above
x.Panel.Video = width.Main-x.Panel.Prediction-3*x.Edge;
y.Panel.Video = height.Main-y.Panel.NNproperties-2*y.Edge-height.line-3*y.Button-height.Button;

% Create all the UI objects in this GUI here so that they can
% be used in any functions in this GUI
hMainFigure         = figure(...
                        'Units','characters',...
                        'MenuBar','none',...
                        'Toolbar','none',...
                        'Position',[x.Main,...
                                    y.Main,...
                                    width.Main,...
                                    height.Main],...
                        'WindowStyle', 'modal');
hNNPropertiesPanel  = uipanel(...
                        'Parent',hMainFigure,...
                        'Units','characters',...
                        'Title','Training Set Properties',... %jvf
                        'Clipping','on',...
                        'Position',[x.Edge,...
                                    height.Main-y.Panel.NNproperties-y.Edge,...
                                    width.Main-2*x.Edge,...
                                    y.Panel.NNproperties]);
hVideoPanel         = uipanel(...
                        'Parent',hMainFigure,...
                        'Units','characters',...
                        'Title','Video Stream',...
                        'Clipping','on',...
                        'Position',[x.Edge,...
                                    height.Main-y.Panel.NNproperties-y.Panel.Video-2*y.Edge,...
                                    x.Panel.Video,...
                                    y.Panel.Video]);
hPredictionPanel    = uipanel(...
                        'Parent',hMainFigure,...
                        'Units','characters',...
                        'Title','Prediction',...
                        'Clipping','on',...
                        'Position',[x.Edge+x.Panel.Video+x.Edge,...
                                    height.Main-y.Panel.NNproperties-y.Panel.Prediction-2*y.Edge,...
                                    x.Panel.Prediction,...
                                    y.Panel.Prediction]);
hPalettePanel   = uipanel(...
                        'Parent',hMainFigure,...
                        'Units','characters',...
                        'Title','Palette',...
                        'Clipping','on',...
                        'Position',[x.Edge+x.Panel.Video+x.Edge,...
                                    height.Main-y.Panel.NNproperties-y.Panel.Video-2*y.Edge,...
                                    x.Panel.Prediction,...
                                    y.Panel.Video-y.Panel.Prediction-1*y.Edge]);
hSectionLine        = uipanel(...
                        'Parent',hMainFigure,...
                        'Units','characters',...
                        'HighlightColor',[0 0 0],...
                        'BorderType','line',...
                        'Title','',...
                        'Clipping','on',...
                        'Position',[x.Edge,...
                                    2*y.Button+height.Button,...
                                    width.Main-2*x.Edge,...
                                    height.line]);
hStartStopButton    = uicontrol(...
                        'Parent',hMainFigure,...
                        'Units','characters',...
                        'Position',[x.Button,...
                                    y.Button,...
                                    width.Button,...
                                    height.Button],...
                        'String','Start Camera',...
                        'Callback',@hStartStopButtonCallback);
hPredictButton      = uicontrol(...
                        'Parent',hMainFigure,...
                        'Units','characters',...
                        'Position',[x.Button*2+width.Button,...
                                    y.Button,...
                                    width.Button,...
                                    height.Button],...
                        'String','Start Prediction',...
                        'Callback',@hPredictButtonCallback);
hExitButton         = uicontrol(...
                        'Parent',hMainFigure,...
                        'Units','characters',...
                        'Position',[width.Main-x.Button-width.Button,...
                                    y.Button,...
                                    width.Button,...
                                    height.Button],...
                        'String','Exit',...
                        'Callback',@hExitButtonCallback);
hNNFileText        = uicontrol(...
                        'Parent',hNNPropertiesPanel,...
                        'Units','characters',...
                        'HorizontalAlignment','right',...
                        'Position',[2,...
                                    3.5,...
                                    14,...
                                    2],...
                        'String','Filename: ',...
                        'Style','text');
hNNFileEdit        = uicontrol(...
                        'Parent',hNNPropertiesPanel,...
                        'Units','characters',...
                        'HorizontalAlignment','left',...
                        'Position',[17,...
                                    4.3,...
                                    111,...
                                    1.4],...
                        'String','Set training set file',...
                        'Enable','inactive',...
                        'Style','edit',...
                        'ButtondownFcn',@hNNFileEditButtondownFcn,...
                        'Callback',@hNNFileEditCallback);
hNNFileButton      = uicontrol(...
                        'Parent',hNNPropertiesPanel,...
                        'Units','characters',...
                        'Callback',@hNNFileButtonCallback,...
                        'Position',[128,...
                                    4.25,...
                                    5.8,...
                                    1.5],...
                        'String','...',...
                        'TooltipString','Select File');
hNNShowFileText       = uicontrol(...
                        'Parent',hNNPropertiesPanel,...
                        'Units','characters',...
                        'HorizontalAlignment','right',...
                        'Position',[2,...
                                    0.6,...
                                    14,...
                                    1],...
                        'String','Training Set: ',... %jvf
                        'Style','text');
hNNShowFilename       = uicontrol(...
                        'Parent',hNNPropertiesPanel,...
                        'Units','characters',...
                        'HorizontalAlignment','left',...
                        'Position',[17,...
                                    0.7,...
                                    80,...
                                    1],...
                        'String','Select file first...',...
                        'Style','text',...
                        'FontSize',10,...
                        'ForegroundColor',[1 0 0],...
                        'FontWeight','bold');
hVideoAxes          = axes(...
                        'Parent',hVideoPanel,...
                        'vis','off',...
                        'Units','characters',...
                        'Position',[x.Edge,...
                                    1.5*y.Edge,...
                                    mVideoWidth/pix2char(1),...
                                    mVideoHeight/pix2char(2)]);
hImage              = image(...
                         zeros(mVideoHeight,mVideoWidth,nBands),...
                         'Parent',hVideoAxes);
hold on
plot([x0, x0+W],...
     [y0, y0+H],...
     'g','LineWidth',2)
hold off
set(hVideoAxes,'vis','off');
hPredictedSign      = uicontrol(...
                        'Parent',hPredictionPanel,...
                        'Units','characters',...
                        'Style','text',...
                        'FontSize',42,...
                        'ForegroundColor',[1 0 0],...
                        'HorizontalAlignment','center',...
                        'Position',[5,...
                                    1,...
                                    7,...
                                    5],...
                        'String','0');

sgn = {'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'};
for i=1:3
    posx = 1; posy = y.Panel.Video-y.Panel.Prediction-1*y.Edge-1.7; dx = 3; dy = 2;
    posx = posx+(i-1)*13;
    for j=1:10
        if 10*(i-1)+j<=length(sgn)
            posy = posy-1.5;
            hPredictedSignText(10*(i-1)+j)= uicontrol(...
                                'Parent',hPalettePanel,...
                                'Units','characters',...
                                'Style','text',...
                                'FontSize',12,...
                                'ForegroundColor',[0 0 0],...
                                'HorizontalAlignment','center',...
                                'Position',[posx,...
                                            posy,...
                                            dx,...
                                            dy],...
                                'String',sgn{10*(i-1)+j});
            hPredictedSignValue(10*(i-1)+j)= uicontrol(...
                                'Parent',hPalettePanel,...
                                'Units','characters',...
                                'Style','text',...
                                'FontSize',10,...
                                'ForegroundColor',[0 0 0],...
                                'HorizontalAlignment','center',...
                                'Position',[posx+4,...
                                            posy+0.1,...
                                            dx+2,...
                                            dy-0.2],...
                                'String','0.00');
        end
    end
end

% Make changes needed for proper look and feel and running on different
% platforms 
prepareLayout(hMainFigure);                            

% Process the command line input arguments supplied when the GUI is
% invoked 
processUserInputs();                            

% Initialize the aslgui using the defaults or custom data given through
% property/value pairs
localUpdate();

% Make the GUI on screen
set(hMainFigure,'visible', 'on');
movegui(hMainFigure,'onscreen');
set(hMainFigure,'Name','TEST American Sign Language (ASL) Recognition System');

% Make the GUI blocking
while strcmp(mAreWeFinished,'no')
    if strcmp(mAreWeLoading,'yes')
        load([mPath,mFile],'-mat','trainingSet'); %jvf
        %mNet = nn.net;  %jvf
        mAreWeLoading = 'no';
    end
    uiwait(hMainFigure);
end

% Return the edited SampleData if it is requested
mOutputArgs{1} = mFrame;
if nargout>0
    [varargout{1:nargout}] = mOutputArgs{:};
end

% Delete and clear the video object
delete(vid)
clear vid
    
    %------------------------------------------------------------------
    function mem_mon(hObject, eventdata)
    % Callback called every 1 second
            out = imaqmem;

        if mTimer>=5
    
            mem_left = out.FrameMemoryLimit - out.FrameMemoryUsed;

            msg = 'Memory left for frames';
            msg2 = 'Memory load';
            low_limit = 400000000;

            if(mem_left > low_limit)
%                 str = sprintf('%s: %d \n%s: %d',msg, mem_left,msg2, out.MemoryLoad); disp(str);
            else
                disp('WARNING: Memory available for frames getting low.');
                disp('Flushing data.')
                flushdata(vid);
            end
            mTimer = 0;
        else
            mTimer = mTimer+1;
        end
        
        
        if strcmp(mAreWePredicting,'yes')%jvf && ~isempty(mNet)
            fprintf('computing at %f.2 Hz.\n',1/toc)
            tic
            if isempty(template) % if first time through do a bunch of setup
                fprintf('getting template\n')
                image1 = getsnapshot(vid);
                if changeColorSpace==1
                    image1=YUY2toRGB(image1);  %jvf2
                end
                image1 = imresize(image1,scl);

                [template,x0,y0,H,W] = Select_patch(image1,0);
                 
                % convert to color map
                %displayImage = image1; % save for later
                
                [image1,map] = rgb2ind(image1,65536);
                
                Lmap = length(map)+1;
                template = rgb2ind(template,map);
                                
                % compute Parzen window
                [ParzenWindow,gx,gy] = Parzen_window(H,W,radius,kernel_type,0); % basically just a gaussian filter
                
                % compute PDF of image 1
                image1_PDF = Density_estim(template,Lmap,ParzenWindow,H,W,0);
            end

            % get image 2
            image2 = getsnapshot(vid);
            if changeColorSpace==1
                image2=YUY2toRGB(image2); %jvf2
            end
            img = image2;  %img is what's passed to recognition fcn
            image2 = imresize(image2,scl);
            displayImage=image2; %jvf2
            [heightImage2, widthImage2,~] = size(image2); %jvf2
            image2=rgb2ind(image2,map); %jvf2
            
            [x,y] = MeanShift_Tracking(image1_PDF,....
                                    image2, ...
                                    Lmap, ...
                                    heightImage2, ...
                                    widthImage2, ...
                                    f_thresh, ...
                                    max_it, ...
                                    x0, ...
                                    y0, ...
                                    H, ...
                                    W, ...
                                    ParzenWindow, ...
                                    gx, ...
                                    gy);
            % update for next iteration                 
            x0 = x;
            y0 = y;

            figure(2)
            imshow(displayImage)
            title ('tracking output')
            hold on
            plot(x0,y0,'ro');
            line([x0, x0],[y0,(y0+H)])
            line([x0, (x0+W)],[(y0+H),(y0+H)])
            line([(x0+W), (x0+W)],[y0,(y0+H)])
            line([x0, (x0+W)],[y0,y0])
            hold off

            
            % do classification
            if mTimer == 0
                 disp('Predicting...\n');
%                 img = getsnapshot(vid);
                
                
                img = rgb2gray(img);
                % pull window out of image 2
                [d,f] = size(img); % height,width
                y0_scaled = ceil(y0/scl);
                x0_scaled = ceil(x0/scl);
                
                %move x0,y0 up/left slightly to ensure full hand is caught
                %jvf2
                border=20; %pixels in the full image space
                if y0_scaled>border
                    y0_scaled=y0_scaled-border;
                else
                    y0_scaled=1;
                end
                if x0_scaled>border
                    x0_scaled=x0_scaled-border;
                else
                    x0_scaled=1;
                end

                %Get new window in frame of image to be sent for recog
                if (y0_scaled +round(H/scl)+border) > d %jvf2
                    yi = d;
                else
                    yi = y0_scaled + round(H/scl)+border; %jvf2
                end
                if (x0_scaled + round(W/scl)+border) > f %jvf2
                    xi = f;
                else
                    xi = x0_scaled + round(W/scl)+border;%jvf2
                end
                
                

                img = img(y0_scaled:yi, x0_scaled:xi);
                figure(3)
                imshow(img)
                hold off
    
                %img=img+15; testing brightness changes
               % wid = 640; hei = 480; scl = 1; wtol = 0.3125; htol = 0.625;
                %img = img(0.5*(1-htol)*hei:0.5*(1+htol)*hei-1,0.5*(1-wtol)*wid:0.5*(1+wtol)*wid-1);
                %img = imresize(img,scl);
                %img = imadjust(img);
                %img = im2bw(img,graythresh(img));
                mFrame=img;%mFrame = reshape(img,1,size(img,1)*size(img,2));

                [mPrediction,~]=testSift(trainingSet,mFrame);
                %jvf- mPrediction = mlpfwd(mNet,mFrame)
    %             str = sprintf('%0.3f   ',mPrediction); disp(str);
                for nclasses=1:size(mPrediction,2)
                    set(hPredictedSignValue(nclasses),'String',sprintf('%0.2f',mPrediction(nclasses)));
                end
                if max(mPrediction)>0.5
                    set(hPredictedSign,'String',char(find(mPrediction==max(mPrediction))+64));
                    set(hPredictedSign,'ForegroundColor',[1 0 0]);
                    set(hPredictedSignText(mPrediction==max(mPrediction)),'ForegroundColor',[1 0 0]);
                    set(hPredictedSignValue(mPrediction==max(mPrediction)),'ForegroundColor',[1 0 0]);
                    set(hPredictedSignText(mPrediction~=max(mPrediction)),'ForegroundColor',[0 0 0]);
                    set(hPredictedSignValue(mPrediction~=max(mPrediction)),'ForegroundColor',[0 0 0]);
                else
                    set(hPredictedSignText,'ForegroundColor',[0 0 0]);
                    set(hPredictedSignValue,'ForegroundColor',[0 0 0]);
                    set(hPredictedSign,'ForegroundColor',[1 0 0]);
                    set(hPredictedSign,'String','0');
                end
            end
           % DON'T PREDICT
%             mPrediction = mlpfwd(mNet,mFrame);
%             
% %             str = sprintf('%0.3f   ',mPrediction); disp(str);
%             for nclasses=1:size(mPrediction,2)
%                 set(hPredictedSignValue(nclasses),'String',sprintf('%0.2f',mPrediction(nclasses)));
%             end
%             if max(mPrediction)>0.5
%                 set(hPredictedSign,'String',char(find(mPrediction==max(mPrediction))+64));
%                 set(hPredictedSign,'ForegroundColor',[1 0 0]);
%                 set(hPredictedSignText(mPrediction==max(mPrediction)),'ForegroundColor',[1 0 0]);
%                 set(hPredictedSignValue(mPrediction==max(mPrediction)),'ForegroundColor',[1 0 0]);
%                 set(hPredictedSignText(mPrediction~=max(mPrediction)),'ForegroundColor',[0 0 0]);
%                 set(hPredictedSignValue(mPrediction~=max(mPrediction)),'ForegroundColor',[0 0 0]);
%             else
%                 set(hPredictedSignText,'ForegroundColor',[0 0 0]);
%                 set(hPredictedSignValue,'ForegroundColor',[0 0 0]);
%                 set(hPredictedSign,'ForegroundColor',[1 0 0]);
%                 set(hPredictedSign,'String','0');
%             end
%         else
            mFrameNumber = [];
        end
        
        
    end

    %------------------------------------------------------------------
    function hNNFileEditButtondownFcn(hObject, eventdata)
    % Callback called the first time the user presses mouse on the data
    % directory editbox 
        set(hObject,'String','');
        set(hObject,'Enable','on');
        set(hObject,'ButtonDownFcn',[]);                uicontrol(hObject);
    end

    %------------------------------------------------------------------
    function hNNFileEditCallback(hObject, eventdata)
    % Callback called when user has changed the neural network filename
        nnfile = get(hObject,'String');
        mFile = nnfile;
    end

    %------------------------------------------------------------------
    function hNNFileButtonCallback(hObject, eventdata)
    % Callback called when the neural network selection button is pressed
        [filename,fpath] = uigetfile(mPath,'Select training set file...');%jvf
        if ~isequal(filename,0)
            mFile = filename;
            mPath = fpath;
            set(hNNFileEdit, 'ButtonDownFcn',[]);            
            set(hNNFileEdit, 'Enable','on');
            set(hNNFileEdit,'String',mFile);
            set(hNNShowFilename,'String',mFile);
            
            mAreWeLoading = 'yes';
            
            mFrame = [];
            localUpdate();
            uiresume;
            
%         elseif isempty(mFrame)
%             set(hPredictedSign,'Visible', 'off');            
        end
    end

    %------------------------------------------------------------------
    function hStartStopButtonCallback(hObject, eventdata)
    % Callback called when the Start/Stop button is pressed
        
        if strcmp(get(hObject,'String'),'Start Camera') 
            set(hObject,'String','Stop Camera');
            preview(vid,hImage)
            start(vid)
            trigger(vid)
        else
            set(hObject,'String','Start Camera');
            set(hPredictButton,'String','Start Prediction');
            mAreWePredicting = 'no';
            stop(vid)
            stoppreview(vid)
        end
    end

    %------------------------------------------------------------------
    function hPredictButtonCallback(hObject, eventdata)
    % Callback called when the Predict button is pressed
        if strcmp(get(hStartStopButton,'String'),'Start Camera')
            disp('You must START CAMERA before starting prediction');
            return
        end
        if strcmp(get(hNNShowFilename,'String'),'Select file first...')
            disp('Frame not captured. Must set training file first.'); %jvf
            return
        end
        if strcmp(get(hObject,'String'),'Start Prediction') 
            set(hObject,'String','Stop Prediction');
            mAreWePredicting = 'yes';
            mFrameNumber = get(vid,'FramesAcquired');
        else
            set(hObject,'String','Start Prediction');
            mAreWePredicting = 'no';
            mFrameNumber = [];
        end
    end

    %------------------------------------------------------------------
    function hExitButtonCallback(hObject, eventdata)
    % Callback called when the Cancel button is pressed
        mFrame =[];
        mAreWeFinished = 'yes';
        uiresume;
        delete(hMainFigure);
    end

    %------------------------------------------------------------------
    function localUpdate
    % helper function that updates the GUI panels

    end

    %------------------------------------------------------------------
    function processUserInputs
    % helper function that processes the input property/value pairs 
    % Apply possible figure and recognizable custom property/value pairs
        for index=1:2:length(mInputArgs)
            if length(mInputArgs) < index+1
                break;
            end
            match = find(ismember({mPropertyDefs{:,1}},mInputArgs{index}));
            if ~isempty(match)  
               % Validate input and assign it to a variable if given
               if ~isempty(mPropertyDefs{match,3}) && ...
                       mPropertyDefs{match,2}(mPropertyDefs{match,1}, ...
                       mInputArgs{index+1})
                   assignin('caller', mPropertyDefs{match,3}, ...
                       mInputArgs{index+1}) 
               end
            else
                try 
                    set(topContainer, ...
                        mInputArgs{index}, mInputArgs{index+1});
                catch
                    % If this is not a valid figure property value pair,
                    % keep the pair and go to the next pair
                    continue;
                end
            end
        end        
    end

    %------------------------------------------------------------------
    function isValid = localValidateInput(property, value)
    % helper function that validates the user provided input property/value
    % pairs. You can choose to show warnings or errors here.
        isValid = false;
        switch lower(property)
            case {'iconwidth', 'iconheight'}
                if isnumeric(value) && value >0
                    isValid = true;
                end
            case 'iconfile'
                if exist(value,'file')==2
                    isValid = true;                    
                end
        end
    end
end % end of aslgui

%------------------------------------------------------------------
function prepareLayout(topContainer)
% This is a utility function that takes care of issues related to
% look&feel and running across multiple platforms. You can reuse
% this function in other GUIs or modify it to fit your needs.
    allObjects = findall(topContainer);
    warning off  %Temporary presentation fix
    try
        titles=get(allObjects(isprop(allObjects,'TitleHandle')), ...
            'TitleHandle');
        allObjects(ismember(allObjects,[titles{:}])) = [];
    catch
    end
    warning on

    % Use the name of this GUI file as the title of the figure
    defaultColor = get(0, 'defaultuicontrolbackgroundcolor');
    if isa(handle(topContainer),'figure')
        set(topContainer,'Name', mfilename, 'NumberTitle','off');
        % Make figure color matches that of GUI objects
        set(topContainer, 'Color',defaultColor);
    end

    % Make GUI objects available to callbacks so that they cannot
    % be changes accidentally by other MATLAB commands
    set(allObjects(isprop(allObjects,'HandleVisibility')), ...
                                     'HandleVisibility', 'Callback');

    % Make the GUI run properly across multiple platforms by using
    % the proper units
    if strcmpi(get(topContainer, 'Resize'),'on')
        set(allObjects(isprop(allObjects,'Units')),'Units','Normalized');
    else
        set(allObjects(isprop(allObjects,'Units')),'Units','Characters');
    end

    % You may want to change the default color of editbox,
    % popupmenu, and listbox to white on Windows 
    if ispc
        candidates = [findobj(allObjects, 'Style','Popupmenu'),...
                           findobj(allObjects, 'Style','Edit'),...
                           findobj(allObjects, 'Style','Listbox')];
        set(findobj(candidates,'BackgroundColor', defaultColor), ...
                               'BackgroundColor','white');
    end
end

