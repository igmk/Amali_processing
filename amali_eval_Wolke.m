function ok = amali_eval_Wolke(DatStr, aerofak, Speichernamepraefix, BSR532soll, BSRAtFit532start, Von, Bis)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% AMALi Auswertung
%
% nadir looking, looping over several lidarratios to find correct lidar
% ratio in cloud,
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% DatStr='170523'
% aerofak=1; %Faktor um NyA Aerosol R?ckstreuung an den aktuellen AMALi
% Flug zu skalieren
% campaign = 'ACLOUD' 'AFLUX'
% Speichernamepraefix = 'Tollertest'
% BSR532soll = 1.3;  angestrebter Referenzwert below the aircraft of BSR532 unter klaren
% Bedingungen   wenn BSR532soll = 'KARL' dann liest er den KARL-NyA Wert
% ein

% BSRAtFit532start   Anfangs(Rate)Wert der unteren Randbedingung vom Klett
% Von / Bis: optional Die Datensatznummern in denen gerechnet werden soll
%Woher weiss er die Daensatznummern
% wird Von / Bis nicht gesetzt rechnet er alles
%
% ok = amali_eval_Wolke('170523', 1, 'Test1', 1.3, 1.4, 2000, 2100)
% ok = amali_eval_Wolke('170523', 1, 'Test1', 'KARL', 1.4)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



ok=-1;


%% INPUT 
if strcmp(DatStr(1:2), '17')
    campaign = 'ACLOUD';
    Angstroem=1.4; % Quelle fuer die Werte ! Sandras paper, Tomasi 2015? ggf. im Wasserdampfpaper.
    speicherdir = '/atm_meas/polar_5_6/amali/data/nadir_processed/cloud/2017/';
    amalidatendir='/lidar4/lidar/amali2011/data/mat/2017/';
elseif strcmp(DatStr(1:2), '19')
    campaign = 'AFLUX';
    Angstroem=1.2; % Quelle fuer die Werte !
    speicherdir = '/atm_meas/polar_5_6/amali/data/nadir_processed/cloud/2019/';
    amalidatendir='/lidar4/lidar/amali2011/data/mat/2019/';
else
    disp('unknown campaign')
    return
end


WvlExpo = 4-Angstroem;

%%
if nargin > 5
    teilzeitjob = 1;
else % if no Date is given it processes everything
    teilzeitjob = 0;
end

%% DEFINITIONS

% wavelength in m (SI units)
wavelenght_532 =5.3207e-7;
wavelenght_355 =3.5471e-7;

%assumed Lidar ratios QUELLE!
% clean marine waere laut Kim 2018 23 +/- 5 fuer 532nm
% 30-50 in arctic haze laut Ritter 2014
% LR532_aerosol=35;

LR532_wolke=15; %initial value, is iterated
LR532_aerosol= 23; %KIM 2018, war 35;
LR532s_aerosol= 23;
LR532s_wolke=15; %initial value, is iterated, orientation by NOTT&DUCK2011
LR355_aerosol=23; %ritter2016 LR etwa gleich wie 532
LR355_wolke=15; %initial value, is iterated

LR532_upperlimit = 60; %war 120 ich finde das vielzuviel BK  vgl zahlen aus NOTT2011
LR532_lowerlimit = 2;  %lowerd to 2 since NOTT 2011
LR532_errorestimate = 5;      % angenommener Fehler im LR  war 10 -war 2 ist jetzt 5 wie in KIM2018- das ist ziemlich wenig


% this are abribretary values, das geht besser quantile? viel
% rechenaufwaendiger.  --> gernzwert variabler machen! dnn passt es vllt.
% auch fuer AFLUX
%minimales backscatterratio das fuer erste Wolkenmaske erreicht werden
%muss.
minimumBSR_cloudmask_ch532=5;
minimumBSR_cloudmask_ch532s=10;   % verrauschter, wollen durch
minimumBSR_cloudmask_ch355=3;



% Faengt Fehler ab. wenn es die ober- und unterschwellen faellt/steigt
% er darf also 2 mal zu Hohes LR erreichen. --> wird dann zuruek auf
% LR532_upperlimit gesetzt bei mehr als 2 gibt er auf
tzlim = 2; hzlim=2;  % limit f?r Hoch- Tiefzahl bei Iter LR ?

% BSRAtFit532start = 1.4;      % besser als Inputparameter

BSRAtFit355start = 1+(BSRAtFit532start-1) ./ 1.5.^WvlExpo; % rechnen 355er Randbedingung aus der von 532 % 
% 1.5=532/355


%Wert um att backscatter abzuschaetzen fuer Wolkenmaske
%minimum backscatter Value to be considered realistic value
BSR532mintrust  = 1.15;
BSR532Smintrust  = 1.15; % das sollte nicht gleich sein. da ist ein denkfehler. 532s ist nicht genauso gross wie 532!/? ------------------------------
BSR355mintrust  = 1 + (BSR532mintrust -1) ./ 1.5.^WvlExpo;




%kann das weg: ?
% BSRAtFiterr=0.2; Fehler ist jetzt 20% von BSRAtFit
% BSR532soll = 1.3;  % ist Inputparameter
% BSR355soll kann erst berechnet werden, wenn BSR532(guteaeroposi) aus KARL
% bekannt ist
% BSR355soll = 1 + (BSR532soll-1) ./ 1.5.^WvlExpo;
% nur f?er den Notfall (NaN im KARL oder keine guteaeroposi):

% wennes aus dem Karl keinen Wert hat
BSR532sollnotfall = 1.3;
BSR532Ssollnotfall = 1.3;
BSR355sollnotfall = 1 + (BSR532sollnotfall-1) ./ 1.5.^WvlExpo;

UeberlappEnde=300; % [m]

pretrigrange=1:400; % um den untergrund zu berechnen
pretriggerbins=405; % wo das Signal started

almostZero = 1e-8; % Signal (P) nur noch Rauschen %fast null
UeberlappEndeposi = round(UeberlappEnde ./ 7.5);

%iteration wird abgebrochen wenn Wert sich nichtmehr veraendert als das
diffisoll = 0.05;  % so gut wollen wir BSR bestimmen


%Hcalcrange =4200;    %2800 in m vom Flugzeug weg. wie weit er in den Boden reinrechnent. (Bei ACLOUD eineige Fluege mit gut 4000m)
%Hcalcrange wird jetzt aus den GPS-Daten bestimmt

%% Rayleighstreuung aus Radiosonde NyA
%warum wird hier nur Juni geladen und nicht Mai?
%ggf. aendern und taegliche RS nutzen
if strcmp(campaign, 'ACLOUD')
    ptuinfile='/atm_meas/awipev/lidar/karl/matlab/ptu/1706.mat';
    ptu = load(ptuinfile);
    ozoinfile='/atm_meas/awipev/lidar/karl/matlab/ozo/1706.mat';
    ozo = load(ozoinfile);
    %koennen wir hier bitte nur die Variablen laden, die wir auch
    %tatsaechlich brauchen?
    load /atm_meas/polar_5_6/amali/data/nadir_processed/cloud/2017/aerosol_background_karl/KARLaverageBSR532ausACLOUD
    KarlH = H; % H wird sp?ter der AMALi Range-vektor
    BSR532Karlmean= BSR532mean; BSR532Karlmedian = BSR532median;
    BSR532SKarlmean= BSR532Smean; BSR532SKarlmedian = BSR532Smedian;
    BSR355Karlmean= BSR355mean; BSR355Karlmedian = BSR355median;
    load /atm_meas/polar_5_6/flight_data/gps/ACLOUDGPS.txt -ascii
    flugzeit=ACLOUDGPS(:,1); %#ok<*NODEF>
    flughoehe=ACLOUDGPS(:,2);
    wo=flughoehe > 10000;
    flughoehe(wo)=NaN;
    
elseif strcmp(campaign, 'AFLUX')
    %pressure, temperature, humidity
    ptuinfile='/atm_meas/awipev/lidar/karl/matlab/ptu/1904.mat';
    ptu=load(ptuinfile);
    ozoinfile='/atm_meas/awipev/lidar/karl/matlab/ozo/1904.mat';
    ozo = load(ozoinfile);
    load /atm_meas/polar_5_6/amali/data/nadir_processed/cloud/2019/aerosol_background_karl/KARLaverageBSR532ausAFLUX
    KarlH = H; % H wird sp?ter der AMALi Range-vektor
    BSR532Karlmean= BSR532mean.*aerofak; BSR532Karlmedian = BSR532median.*aerofak;
    BSR532SKarlmean= BSR532Smean.*aerofak; BSR532SKarlmedian = BSR532Smedian.*aerofak;
    BSR355Karlmean= BSR355mean.*aerofak; BSR355Karlmedian = BSR355median.*aerofak;
    
    load /atm_meas/polar_5_6/flight_data/gps/AFLUXGPS.txt -ascii
    flugzeit=AFLUXGPS(:,1);
    flughoehe=AFLUXGPS(:,2);
    wo=flughoehe > 10000; %expected value approx 3000 to sort out funny values
    flughoehe(wo)=NaN;
end

Hcalcrange = max(flughoehe) + 50;    %2800 in m vom Flugzeug weg. wie weit er in den Boden reinrechnent. (Bei ACLOUD eineige Fluege mit gut 4000m)

meanO3profile=(mymean(ozo.OZOO3Density'))'; %ist ozon ueberhaupt wirklich relevant?

Density = density(ptu.PTUPressure, ptu.PTUPressure./100, ptu.PTUTemperature,ones(size(ptu.PTUTemperature)).*2);

%Extinktion nur Streuanteil (der 99% ausmacht)
AlphaRayleigh_532 = Density .* raytotwq( wavelenght_532, ptu.PTUTemperature, Density);
AlphaRayleigh_355 = Density .* raytotwq( wavelenght_355, ptu.PTUTemperature, Density);
% Rayleigh R?ckstreuung (die schwach polaris.- und temp- abhaengig ist
% wichtig: Streuung =  Luftdichte (Density) mal Wirkungsquerschnitt
%raybckwq rechnet Wirkungsquerschnitt aus

%betarayleigh pure air
BetaRayleigh_532=Density.*raybckwq (wavelenght_532,'p','p', ptu.PTUTemperature, Density);
BetaRayleigh_532S=Density.*raybckwq (wavelenght_532,'p','s', ptu.PTUTemperature, Density);
BetaRayleigh_355=Density.*raybckwq (wavelenght_355,'p','u', ptu.PTUTemperature, Density);

% Korrektur durch molek. Absorption, die praktisch nur durch O3
% vor allem wichit in Strato
ptu.dimension=size(AlphaRayleigh_355);
for j=1:ptu.dimension(2)
    AbsorbtionOzone.ch532=meanO3profile.*o3abswq(wavelenght_532,ptu.PTUTemperature(:,j));
    AbsorbtionOzone.ch355=meanO3profile.*o3abswq(wavelenght_355,ptu.PTUTemperature(:,j));
    AlphaRayleigh_532(:,j)=AlphaRayleigh_532(:,j)+AbsorbtionOzone.ch532;
    AlphaRayleigh_355(:,j)=AlphaRayleigh_355(:,j)+AbsorbtionOzone.ch355;
end


% fuer Jun 2017 bei 86 Sonden Streuung der Luftdichte etwa 7% 
%
% gemittelte Luftdichte-Profile aus Ny-Alesund --> mittlere Rayleigh werte ueber den
% Monat
% noch Ny_Alesund H?henvektor
%Abkuerzungen ausschreiben!
NAlRay532=(mymean(AlphaRayleigh_532'))';
NAlRay355=(mymean(AlphaRayleigh_355'))';
NBeRa532=(mymean(BetaRayleigh_532'))';
NBeRa355=(mymean(BetaRayleigh_355'))';
NBeRa532S=(mymean(BetaRayleigh_532S'))';
NH = ptu.PTUHeight(:,1); %#ok<NODEF>
NDensity=(mymean(Density'))';

% In den ersten bins aus Ny-Alesund kann NaN stehen, dies interpolieren wir
% weg
tmp=real(log(NAlRay532)); %Gerade kommt raus, weil Rayleigh profil quasi exponentiell (folgt Luftdichte)
wo=find(isnan(tmp(1:20)));
if ~isempty(wo)
    woend=wo(end);
    st=mymean(diff(tmp(woend+1:woend+11)));
    for jj=woend:-1:1
        tmp(jj)=tmp(woend+1)-(woend+1-jj).*st;
    end
end
NAlRay532 = exp(tmp);

tmp=real(log(NAlRay355));
wo=find(isnan(tmp(1:20)));
if ~isempty(wo)
    woend=wo(end);
    st=mymean(diff(tmp(woend+1:woend+11)));
    for jj=woend:-1:1
        tmp(jj)=tmp(woend+1)-(woend+1-jj).*st;
    end
end
NAlRay355 = exp(tmp);

tmp=real(log(NBeRa532));
wo=find(isnan(tmp(1:20)));
if ~isempty(wo)
    woend=wo(end);
    st=mymean(diff(tmp(woend+1:woend+11)));
    for jj=woend:-1:1
        tmp(jj)=tmp(woend+1)-(woend+1-jj).*st;
    end
end
NBeRa532 = exp(tmp);

tmp=real(log(NBeRa532S));
wo=find(isnan(tmp(1:20)));
if ~isempty(wo)
    woend=wo(end);
    st=mymean(diff(tmp(woend+1:woend+11)));
    for jj=woend:-1:1
        tmp(jj)=tmp(woend+1)-(woend+1-jj).*st;
    end
end
NBeRa532S = exp(tmp);


tmp=real(log(NBeRa355));
wo=find(isnan(tmp(1:20)));
if ~isempty(wo)
    woend=wo(end);
    st=mymean(diff(tmp(woend+1:woend+11)));
    for jj=woend:-1:1
        tmp(jj)=tmp(woend+1)-(woend+1-jj).*st;
    end
end
NBeRa355 = exp(tmp);






% noch nicht fertig
% % Rayleighstreuung aus Dropsonde
% dropfilepath='/lidar4/bkulla/ACLOUD2017/dropsondes/2017/06/';
% day='/02/';
% dropname=''
% dropfilename=[dropfilepath day dropname]
% dropT=ncread(dropfilename,'');
% dropH=ncread(dropfilename,'');
% dropP=ncread(dropfilename,'');
% dropdens = density(dropP, dropP./100, dropT,ones(size(dropT)).*2);
%
% %Extinktion nur Streuanteil (der 99% ausmacht)
% AlRay532 = dropdens .* raytotwq( wavelenght_532, dropT, dropdens);
% AlRay355 = dropdens .* raytotwq( wavelenght_355, dropT, dropdens);
% % Rayleigh R?ckstreuung (die schwach polaris.- und temp- abhaengig ist
% % wichtig: Streuung =  Luftdichte (Density) mal Wirkungsquerschnitt
% BeRa532=dropdens.*raybckwq (wavelenght_532,'p','p', dropT, dropdens);
% BeRa532S=dropdens.*raybckwq (wavelenght_532,'p','s', dropT, dropdens);
% BeRa355=Density.*raybckwq (wavelenght_355,'p','p', ptu.PTUTemperature, Density);
% % Korrektur durch molek. Absorption, die praktisch nur durch O3
% % vor allem wichit in Strato - wenn es kein Ozon aus Dropsonde gibt





%% Einlesen der Lidardaten
% und definitionen leerer Variablen
datum=[DatStr '/'];
suchfile=[amalidatendir datum '*.mat'];
files=findfile(suchfile);
NofFiles = length(files(:,1));
if NofFiles >1
    disp('more than one dataset, looping over all datasets')
end

if isempty(files)
    ok=-1;
    disp(['no data for: ' datum(1:6)])
    return
else
    % jetzt geht es aber mal so richtig los
    ok = NofFiles;
    for kk=1:NofFiles %Schleife ?ber alle Datens?tze
        disp(['processing dataset ' num2str(kk) ' of ' num2str(ok)])
        load(files(kk,:))
        wostrich=findstr(files(kk,:),'/'); %#ok<*FSTR>           da wo der slash ist
        if length(wostrich)>1, wostrich=wostrich(end); end
        womat= findstr(files(kk,:), '.mat');
        filename = files(kk,wostrich+1:womat-1);
        datasize=size(alldata);
        entries=datasize(2);
        bins=datasize(3);
        data532=(reshape(alldata(1,:,:),entries, bins));   % Format umgedreht jetzt wie KARL %hoehe 1. Dimensio, zeit 2. dimension
        data532s=(reshape(alldata(3,:,:),entries, bins));  % size =[H, Zeiten]
        data355=(reshape(alldata(5,:,:),entries, bins));
        data532c=(reshape(alldata(2,:,:),entries, bins));
        data532sc=(reshape(alldata(4,:,:),entries, bins));
        data355c=(reshape(alldata(6,:,:),entries, bins));
        
        
        matlabzeit = (allinfo(1,:)/86400) + datenum(1904,1,1);
        
        H=(0:7.5:Hcalcrange)';    dH=7.5;    lim=50; %(Limit Signal hat Wolken)
        LH=length(H);
        P532A=zeros(entries,LH);
        P532SA=zeros(entries,LH);
        P355A=zeros(entries,LH);
        P532C=zeros(entries,LH);
        P532SC=zeros(entries,LH);
        P355C=zeros(entries,LH);
        
        % Im ersten Datensatz (k=1) wandeln wir die Karl H?hen und BSRWerte auf das
        % AMALi Gitter um (auf den Kopf gestellt )
        
        if kk==1
            if BSR532soll=='KARL'
                [KarlHzumBoden,indexx]=sort(KarlH,'descend');
                BSR532KarlmedianzumBoden = BSR532Karlmedian(indexx);
                %BSR532KarlmeanzumBoden = BSR532Karlmean(indexx);
                BSR532SKarlmedianzumBoden = BSR532SKarlmedian(indexx);
                %BSR532SKarlmeanzumBoden = BSR532SKarlmean(indexx);
                BSR355KarlmedianzumBoden = BSR355Karlmedian(indexx);
                %BSR355KarlmeanzumBoden = BSR355Karlmean(indexx);
                % jetzt m?ssen wir das auf das H?hengitter des Amali interpolieren
                BSR532Karlmedianvgl = interp1(KarlHzumBoden, BSR532KarlmedianzumBoden, H);
                %BSR532Karlmeanvgl = interp1(KarlHzumBoden, BSR532KarlmeanzumBoden, H);
                BSR532SKarlmedianvgl = interp1(KarlHzumBoden, BSR532SKarlmedianzumBoden, H); % <------------------------------------- warum wird dieser Wert nicht benutzt
                %BSR532SKarlmeanvgl = interp1(KarlHzumBoden, BSR532SKarlmeanzumBoden, H);
                BSR355Karlmedianvgl = interp1(KarlHzumBoden, BSR355KarlmedianzumBoden, H);
                %BSR355Karlmeanvgl = interp1(KarlHzumBoden, BSR355KarlmeanzumBoden, H);
            else
                BSR532Karlmedianvgl =  BSR532sollnotfall;
                %BSR532Karlmeanvgl =  BSR532sollnotfall;
                BSR532SKarlmedianvgl =  BSR532Ssollnotfall;
                %BSR532SKarlmeanvgl =  BSR532Ssollnotfall;
                BSR355Karlmedianvgl =  BSR355sollnotfall;
                %BSR355Karlmeanvgl =  BSR355sollnotfall;
            end
        end
        
        P532Abackground=zeros(entries,1);
        P532SAbackground=zeros(entries,1);
        P355Abackground=zeros(entries,1);
        %fuer die counting kanaele machen wir keine background korrektur
        %P532Cbackground=zeros(entries,1);
        %P532SCbackground=zeros(entries,1);
        %P355Cbackground=zeros(entries,1);
        
        %versatz im AMALi
        vs532p=-1;
        vs532s=-1;
        vs355=+1;
        
        %unrealistische Spikes rausfiltern
        wo = data532c > 3.2e4;
        %data532creserve=data532c;
        data532c(wo)=NaN;
        wo = data532sc > 3.0e4;
        %data532screserve=data532sc;
        data532sc(wo)=NaN;
        wo = data355c > 3.2e4;
        %data355creserve=data355c;
        data355c(wo)=NaN;
        
        
        %Backgound
        for j=1:entries
            P532Abackground(j) = mymean(data532(j,pretrigrange));
            P532A(j,:)=data532(j,pretriggerbins+1:pretriggerbins+LH)- P532Abackground(j);
            P532SAbackground(j) = mymean(data532s(j,pretrigrange));
            P532SA(j,:)=data532s(j,pretriggerbins+1:pretriggerbins+LH)-P532SAbackground(j);
            P355Abackground(j) = mymean(data355(j,pretrigrange));
            %substract background
            P355A(j,:)=data355(j,pretriggerbins+1:pretriggerbins+LH)- P355Abackground(j);
            P532C(j,:)=data532c(j,vs532p+pretriggerbins+1:vs532p+pretriggerbins+LH)-mymean(data532c(j,pretrigrange));
            P532SC(j,:)=data532sc(j,vs532s+pretriggerbins+1:vs532s+pretriggerbins+LH)-mymean(data532sc(j,pretrigrange));
            P355C(j,:)=data355c(j,vs355+pretriggerbins+1:vs355+pretriggerbins+LH)-mymean(data355c(j,pretrigrange));
            
        end
        
        %rechnen mit Lidarsigal PKlett
        %transponiert damit dimensionen zu Karl-logik passen, Hoehe*Zeit
        P532Klett =P532A';
        P532SKlett =P532SA';
        P355Klett= P355A';
        % counting Kanaele nutzen wir nicht. ggf. hinzufuegen, falls
        % aersol Auswertung von interesse.
        %P532CKlett =P532C';
        %P532SCKlett =P532SC';
        %P355CKlett= P355C';
        
        %warum werden hier sachen doppelt abgelegt?
        %         P532fuerdepol= P532A';
        %         P532Sfuerdepol= P532SA';
        %         VolDep532 = P532Sfuerdepol ./ P532fuerdepol;
        
        
        %Versuch analog und counting zusammenzusetzen
        %"gesamt" sind die zusammengesetzen Profile
        % diese in counts wie die pc-Profile
        % wo532scompare=find(P532SCKlett < 10 & P532SCKlett > 4);
        % fktoranapc532s = mymean(P532SKlett(wo532scompare))./mymean(P532SCKlett(wo532scompare));
        % P532Sklettgesamt = P532Sklett ./ fktoranapc532s;
        
        
        %negative Werte durch fast nulls ersetzen fuer klatt
        wo=P532Klett < almostZero; P532Klett(wo)=almostZero;
        wo=P532SKlett < almostZero; P532SKlett(wo)=almostZero;
        wo=P355Klett < almostZero; P355Klett(wo)=almostZero;
        
        %definitionen von leeren teilen
        P532Kletterr=zeros(size(P532Klett));
        backgroundnoise532=zeros(entries,1);
        P532SKletterr=zeros(size(P532SKlett));
        backgroundnoise532S=zeros(entries,1);
        P355Kletterr=zeros(size(P355Klett));
        backgroundnoise355=zeros(entries,1);
        
        
        %SNR berechnen
        %wo kommen die 1.5 her? BK: geloescht da aus meiner Sicht kein Mehrwert -------------------------------------------
        %
        for j=1:entries
            backgroundnoise532(j)=std(data532(j,pretrigrange)).*1;
            P532Kletterr(:,j)=real(sqrt(P532Klett(:,j)))+backgroundnoise532(j);
            backgroundnoise532S(j)=std(data532s(j,pretrigrange)).*1;
            P532SKletterr(:,j)=real(sqrt(P532SKlett(:,j)))+backgroundnoise532S(j);
            backgroundnoise355(j)=std(data355(j,pretrigrange)).*1;
            P355Kletterr(:,j)=real(sqrt(P355Klett(:,j)))+backgroundnoise355(j);
        end
        SNR532=P532Klett./P532Kletterr;
        SNR532S=P532SKlett./P532SKletterr;
        SNR355=P355Klett./P355Kletterr;
        
        
        
        % Rayleighgr?ssen + Density auf das Amaligitter
        NAlRay532aufl=interp1(NH,NAlRay532,H);
        AlRay532=NAlRay532aufl(end:-1:1);
        NAlRay355aufl=interp1(NH,NAlRay355,H);
        AlRay355=NAlRay355aufl(end:-1:1);
        NBeRa532aufl=interp1(NH,NBeRa532,H);
        BeRa532=NBeRa532aufl(end:-1:1);
        NBeRa532Saufl=interp1(NH,NBeRa532S,H);
        BeRa532S=NBeRa532Saufl(end:-1:1);
        NBeRa355aufl=interp1(NH,NBeRa355,H);
        BeRa355=NBeRa355aufl(end:-1:1);
        NDensityaufl=interp1(NH,NDensity,H);
        Density=NDensityaufl(end:-1:1);
        
        %% First Klett =====================================================
        %adjusting assumption at lower boundary condition
        
        % Nun der schlaue Klett
        % wir brauchen f?r jeden Kanal:
        % BSRAtFitarr = das array der BSR-Werte f?r den Fit
        % FitRange = die H?he von, bis in der im Durchschnitt BSR=BSRAtFitarr sein
        % soll z.B. [2000, 2400]
        % H: Hoehenvektor
        % P: das Lidarprofil
        % Perr "error" Fehler des Lidarprofils
        % LRarr= array des Lidarverh?ltnisses, gleich gro? wie P
        % ALRay532 / BeRa532 die Rayleogh-Extinktions und R?ckstreuwerte
        % klettinv_ableit4 spuckt aus:
        % 1) Beta = Gesamtr?ckstreuung (aer+Rayleigh)
        % 2) dBdR die partielle Ableitung d Beta_aer / d Randbedingung
        % 3) dBdLR= die part. Ableit. d Beta_aer / d Lidarverh?eltnis
        % 4) dBdP: die part. Abl. d Beta_aer / d Perr
        % 5) Vorschlag CLidar: die Lidarkonstane aus L?sung Beta, LR und elast.
        % Lidargleichung
        
        %% Definitionen:
        % f?r alle Farben:
        FitRangearr=zeros(2,entries);
        Wolkenmaske=zeros(size(P532Klett)); %
        dimen=size(P532Klett);
        
        % f?r 532P
        LR532arr=ones(size(P532Klett)).*LR532_wolke;    % es geht ja um Wolken
        LR532arrerr=ones(size(P532Klett)).*LR532_errorestimate;
        BSRAtFit532arr=ones(entries,1).* BSRAtFit532start;
        Btemp532=zeros(LH,1); Btemp532_2=zeros(LH,1);    Btemp532err=Btemp532;
        Betaaer532=zeros(LH,1); Betaaer532err=Btemp532;  BetaAer532_2=zeros(LH,1);
        BetaAer532Klett=zeros(size(P532Klett)); BetaAer532Kletterr=zeros(size(P532Klett));
        BetaAer532Klettfest=zeros(size(P532Klett)); BetaAer532Klettfesterr=zeros(size(P532Klett));
        dBeta532dLR=zeros(size(P532Klett));
        dBeta532dR=zeros(size(P532Klett));
        dBeta532dP=zeros(size(P532Klett));
        BSR532Klett=zeros(size(P532Klett)); BSR532Kletterr=zeros(size(P532Klett));
        BSR532Klettfest=zeros(size(P532Klett)); BSR532Klettfesterr=zeros(size(P532Klett));
        C532Lidar=zeros(size(P532Klett));
        AlphaAer532= zeros(size(P532Klett));
        AlphaAer532err= zeros(size(P532Klett));
        attenu532P= zeros(size(P532Klett));       attenu532Perr= zeros(size(P532Klett));
        Abbruch532 = zeros(dimen(2),1);
        BSR532sollarr = zeros(dimen(2),1);
        % Abbruch532 gibt Abbruchkriterium an:
        % 0:hat gar nicht LR angepa?t
        % 1: normale Konvergenz
        % 2: LR = 5 (unteres Limit)
        % 3: LR = LR532_upperlimit (oberes Limit)
        % 4: hat sich totiteriert ohne Konvergenz
        % 5: guteaeroposi = 0;
        %
        bininlrschleife532=zeros(entries,1);
        
        %ein reines Rayleighprofil
        Ptheo532=2.*BeRa532./H.^2.*exp(-2.*qdrupvar(H,2.*AlRay532));
        
        
        % f?r 532S
        LR532Sarr=ones(size(P532Klett)).*LR532_wolke;    % es geht ja um Wolken
        LR532Sarrerr=ones(size(P532Klett)).*LR532_errorestimate;
        BSRAtFit532Sarr=ones(entries,1).* BSRAtFit532start;
        Btemp532S=zeros(LH,1); Btemp532S_2=zeros(LH,1);    Btemp532Serr=Btemp532S;
        Betaaer532S=zeros(LH,1); Betaaer532Serr=Btemp532S;  BetaAer532S_2=zeros(LH,1);
        BetaAer532SKlett=zeros(size(P532SKlett)); BetaAer532SKletterr=zeros(size(P532SKlett));
        BetaAer532SKlettfest=zeros(size(P532SKlett)); BetaAer532SKlettfesterr=zeros(size(P532SKlett));
        BetaAer532SKlettausP=zeros(size(P532SKlett)); BetaAer532SKlettausPerr=zeros(size(P532SKlett));
        dBeta532SdLR=zeros(size(P532SKlett));
        dBeta532SdR=zeros(size(P532SKlett));
        dBeta532SdP=zeros(size(P532SKlett));
        BSR532SKlett=zeros(size(P532SKlett)); BSR532SKletterr=zeros(size(P532SKlett));
        BSR532SKlettfest=zeros(size(P532SKlett)); BSR532SKlettfesterr=zeros(size(P532SKlett));
        BSR532SKlettausP=zeros(size(P532SKlett)); BSR532SKlettausPerr=zeros(size(P532SKlett));
        C532SLidar=zeros(size(P532SKlett));
        AlphaAer532S= zeros(size(P532SKlett));
        AlphaAer532Serr= zeros(size(P532SKlett));
        attenu532S= zeros(size(P532SKlett));       attenu532Serr= zeros(size(P532SKlett));
        Abbruch532s = zeros(dimen(2),1);
        BSR532Ssollarr = zeros(dimen(2),1);
        
        bininlrschleife532S=zeros(entries,1);
        Ptheo532S=2.*BeRa532S./H.^2.*exp(-2.*qdrupvar(H,2.*AlRay532));
        
        
        % f?r 355P
        LR355arr=ones(size(P355Klett)).*LR355_wolke;    % es geht ja um Wolken
        LR355arrerr=ones(size(P355Klett)).*LR532_errorestimate;
        BSRAtFit355arr=ones(entries,1).* BSRAtFit355start;
        Btemp355=zeros(LH,1); Btemp355_2=zeros(LH,1);    Btemp355err=Btemp355;
        Betaaer355=zeros(LH,1); Betaaer355err=Btemp355;  BetaAer355_2=zeros(LH,1);
        BetaAer355Klett=zeros(size(P355Klett)); BetaAer355Kletterr=zeros(size(P355Klett));
        BetaAer355Klettfest=zeros(size(P355Klett)); BetaAer355Klettfesterr=zeros(size(P355Klett));
        dBeta355dLR=zeros(size(P355Klett));
        dBeta355dR=zeros(size(P355Klett));
        dBeta355dP=zeros(size(P355Klett));
        BSR355Klett=zeros(size(P355Klett)); BSR355Kletterr=zeros(size(P355Klett));
        BSR355Klettfest=zeros(size(P355Klett)); BSR355Klettfesterr=zeros(size(P355Klett));
        C355Lidar=zeros(size(P355Klett));
        AlphaAer355= zeros(size(P355Klett));
        AlphaAer355err= zeros(size(P355Klett));
        attenu355P= zeros(size(P355Klett));       attenu355Perr= zeros(size(P355Klett));
        Abbruch355 = zeros(dimen(2),1);
        BSR355sollarr = zeros(dimen(2),1);
        
        bininlrschleife355=zeros(entries,1);
        
        %profil mit keinem Aerosol
        Ptheo355=2.*BeRa355./H.^2.*exp(-2.*qdrupvar(H,2.*AlRay355));
        
        
        %%
        if teilzeitjob==1
            start = Von; ende = Bis;
        else
            start = 1; ende = entries;
        end
        teiler=floor(ende./10);
        %%
        
        
        % Loop over all time steps
        for j=  2000:5000%start:ende   %1:entries    %2000:5000  start:ende
            
            %display sth every now and then
            if (mod(j,teiler)) ==0, disp(['Profile: ' num2str(j) ' von ' num2str(ende)]), end
            
            if j ==5000
                q=1;
            end
            
            
            % Definitionen innerhalb eines Zeitschrittes
            %psoll sind die profile die ich haette messen mussen wenn klare
            %luft gewesen waere (lidarkonstante abgeschaetzt) 
            Psoll532=Ptheo532 ./ (Ptheo532(UeberlappEndeposi).*P532Klett(UeberlappEndeposi,j));
            Psoll532S=Ptheo532S ./Ptheo532S(UeberlappEndeposi).*P532SKlett(UeberlappEndeposi,j);
            Psoll355=Ptheo355 ./Ptheo355(UeberlappEndeposi).*P355Klett(UeberlappEndeposi,j);
            
            ichmerkmirkomischepositionen = 0;
            
              %Bereich wo die untere Randbedingung gesetzt wird
            [~,posi]=min(abs(matlabzeit(j)-flugzeit));
            hwo2=flughoehe(posi)-7.5;
            hwo1=flughoehe(posi)-107.5;
            FitRangearr(1,j)=hwo1; FitRangearr(2,j)=hwo2;  
            
            
            % "select" die guten H?henbins, in denen gerechnet werden soll.
            %Abfangen das definiteiv nichts komisches in den Klett reingeht
            %532P
            Sel532P = connrnge( H >= 0 & H <= flughoehe(posi)-2000 & ...
                P532Klett(:,j) > 0 & ...
                Density(:,1) > 0, 1);
            if length(Sel532P) > 1
                Sel532P = (Sel532P(1):Sel532P(2));
            else
                Sel532P = [];
            end
            
            % 532S
            Sel532S = connrnge( H >= 0 & H <= flughoehe(posi)-2000 & ...
                P532SKlett(:,j) > 0 & ...
                Density(:,1) > 0, 1);
            if length(Sel532S) > 1
                Sel532S = (Sel532S(1):Sel532S(2));
            else
                Sel532S = [];
            end
            
            
            % 355
            Sel355P = connrnge( H >= 0 & H <= flughoehe(posi)-2000 & ...
                P355Klett(:,j) > 0 & ...
                Density(:,1) > 0, 1);
            if length(Sel355P) > 1
                Sel355P = (Sel355P(1):Sel355P(2));
            else
                Sel355P = [];
            end
          
            
          
            
            
            % wir rechnen je ein erstes Mal, nur um zu sehen, wo Wolken sind
            % wenn FitRangearr(:,j) ungefaehr gleich Hcalcrange, dann ist das
            % Lidarsignal durch die Wolke durchgekommen, also ist die Wolke d?nn und
            % damit hat BSRAtFit einen Einflu?. Dann k?nnte Beta zu klein werden
            % wir iterieren BSRAtFit532arr(j) bis Beta nicht mehr offensichtlich zu
            % klein ist und benutzen median(btemp) > 1.05 als Abbruchkriterium
            % Sinn: eine Wolkenmaske zu erstellen
            
            %% First Klett --> welches BSRstfit wird benoetigt
            
            % 532P
            condi=1; iter=0; itmax=600;
            hz532=0;
            [VoI,BiI]= minintsuche(abs(Psoll532(Sel532P(40:length(Sel532P)))-P532Klett(Sel532P(40:length(Sel532P)),j)),40); %was passiert hier?
            clearint=VoI:BiI;
            while condi
                iter = iter+1;
                if iter > itmax, condi = 0; end
                
                BSRAtFiterr = BSRAtFit532arr(j) ./ 5;
                [Beta, dBdR532, dBdLR532, dBdP532, CLidar] = klettinv_ableit4( BSRAtFit532arr(j), FitRangearr(:,j), H(Sel532P), P532Klett(Sel532P,j), P532Kletterr(Sel532P,j), ...
                    LR532arr(Sel532P,j), AlRay532(Sel532P,1), BeRa532(Sel532P,1));
                Betaaer532(Sel532P)=Beta-BeRa532(Sel532P,1);
                Betaaer532err(Sel532P,j)=abs(dBdR532.*BSRAtFiterr)+abs(dBdLR532.*LR532arrerr(Sel532P,j))+abs(dBdP532.*P532Kletterr(Sel532P,j));
                Btemp532(Sel532P)=Beta./BeRa532(Sel532P,1); Btemp532err(Sel532P)=Betaaer532err(Sel532P,j)./BeRa532(Sel532P,1);
                tmp=mymean(Btemp532(Sel532P(clearint)));
                
                
                %BSRAtFit532arr(j)+1
                [Beta2, dBdR5322, dBdLR5322, dBdP5322, CLidar2] = klettinv_ableit4( BSRAtFit532arr(j)+1, FitRangearr(:,j), H(Sel532P), P532Klett(Sel532P,j), P532Kletterr(Sel532P,j), ...
                    LR532arr(Sel532P,j), AlRay532(Sel532P,1), BeRa532(Sel532P,1)); %BSRAtFit is increased by 1,  
                BetaAer532_2(Sel532P)=Beta2-BeRa532(Sel532P,1);
                %BetaAer532_2err(Sel532P,j)=abs(dBdR5322.*BSRAtFiterr)+abs(dBdLR5322.*LR532arrerr(Sel532P,j))+abs(dBdP5322.*P532Kletterr(Sel532P,j));
                Btemp532_2(Sel532P)=Beta2./BeRa532(Sel532P,1); %Btemp532_2err(Sel532P)=BetaAer532_2err(Sel532P,j)./BeRa532(Sel532P,1);
                tmp2=mymean(Btemp532_2(Sel532P(clearint)));
                
                deltasoll = BSR532mintrust - tmp; %kommen wir oben in den Bereich, den wir erwarten wuerden?
                deltab=(tmp2-tmp);
                if abs(deltasoll) > 0.01 % passt noch nicht
                    %w=(BSR532sollarr(j) - tmp) ./ deltab;
                    BSRAtFit532arr(j) = BSRAtFit532arr(j) + 1./deltab.*deltasoll; %das BSRfit arr wir entsprechen der linearen Approximation angepasst -- warum mal deltasoll und nicht BSR532mintrust !!!!!!
                    if BSRAtFit532arr(j) > 1e6, hz532=hz532+1; BSRAtFit532arr(j) =1e6; end
                else %
                    condi=0; %disp('bringt nichts mehr'),
                end
                diffi = abs(tmp - BSR532mintrust);
                if abs(diffi) < diffisoll, condi=0;  end  % normales Ende
                if hz532 >hzlim, condi = 0; end   % Rdbeding. irrelevant
                
                % deltab
                % qq=BSRAtFit532arr(j)
            end % 1. while %hat der das BSRfit hier ueberhaupt ordentlich veraendert? 
            
            
            if tmp < BSR532mintrust-diffisoll  % noetig falls iter > itmax.
                Btemp532=Btemp532./tmp.*BSR532mintrust; %????? --------------------------------------------!!!! Mittlerwert wird auf 1.15 geforced
                Abbruch532(j) = Abbruch532(j)+0.001;% <--------------------------------------------------hier laeuft er sehr oft rein. -- aber ist das ein problem? Muss nur markiert werden damit wir wissen, dass den unteren Werten nicht vertraut werden kann. 
                %disp(['bsr at fit kann nicht bestimmt werden' string(j)])
            end
            %Was ist das? warum sucht er da was raus? ist etwas verloren
            %gegangen?
            %----------------------------------------------------------------------
            %wo532= find(Btemp532 < minimumBSR_cloudmask_ch532 );    %& H< hwo1);
            
           
            % 532S
            condi=1; iter=0; itmax=600;
            hz532S=0;
 
            [VoI,BiI]= minintsuche(abs(Psoll532S(Sel532S(40:length(Sel532S)))-P532SKlett(Sel532S(40:length(Sel532S)),j)),40);
            clearint=VoI:BiI;
            while condi
                iter = iter+1;
                if iter > itmax, condi = 0; end
                
                BSRAtFiterr = BSRAtFit532Sarr(j) ./ 5;
                [Beta, dBdR, dBdLR, dBdP532, CLidar] = klettinv_ableit4( BSRAtFit532Sarr(j), FitRangearr(:,j), H(Sel532S), P532SKlett(Sel532S,j), P532SKletterr(Sel532S,j), ...
                    LR532Sarr(Sel532S,j), AlRay532(Sel532S,1), BeRa532S(Sel532S,1)); %BeRa = Beta Rayleigh (senkrecht)
                Betaaer532S(Sel532S)=Beta-BeRa532S(Sel532S,1);
                Betaaer532Serr(Sel532S,j)=abs(dBdR.*BSRAtFiterr)+abs(dBdLR.*LR532Sarrerr(Sel532S,j))+abs(dBdP532.*P532SKletterr(Sel532S,j));
                Btemp532S(Sel532S)=Beta./BeRa532S(Sel532S,1); Btemp532Serr(Sel532S)=Betaaer532Serr(Sel532S,j)./BeRa532S(Sel532S,1);
                tmp=mymean(Btemp532S(Sel532S(clearint)));
                
                [Beta2, dBdR2, dBdLR2, dBdP5322, CLidar2] = klettinv_ableit4( BSRAtFit532Sarr(j)+1, FitRangearr(:,j), H(Sel532S), P532SKlett(Sel532S,j), P532SKletterr(Sel532S,j), ...
                    LR532Sarr(Sel532S,j), AlRay532(Sel532S,1), BeRa532S(Sel532S,1));
                Betaaer532S_2(Sel532S)=Beta2-BeRa532S(Sel532S,1);
                %Betaaer2err(Sel,j)=abs(dBdR2.*BSRAtFiterr)+abs(dBdLR2.*LR532arrerr(Sel,j))+abs(dBdP5322.*Perr(Sel,j));
                Btemp532S_2(Sel532S)=Beta2./BeRa532S(Sel532S,1); %Btemp2err(Sel)=Betaaer2err(Sel,j)./BeRa532(Sel,1);
                tmp2=mymean(Btemp532S_2(Sel532S(clearint)));
                
                deltasoll = BSR532Smintrust - tmp;
                deltab=(tmp2-tmp);
                if abs(deltasoll) > 0.01
                    %w=(BSR532Ssollarr(j) - tmp) ./ deltab;
                    BSRAtFit532Sarr(j) = BSRAtFit532Sarr(j) +1./deltab.*deltasoll;
                    BSRAtFit532Sarr(j)
                    if BSRAtFit532Sarr(j) > 1e6, hz532S=hz532S+1; BSRAtFit532Sarr(j) =1e6; end
                else
                    condi=0; %disp('bringt nichts mehr'),
                end
                diffi = abs(tmp - BSR532Smintrust);
                if abs(diffi) < diffisoll, condi=0;  end  % normales Ende
                if hz532S >hzlim, condi = 0; end   % Rdbeding. irrelevant
                
                % deltab
                % qq=BSRAtFit532Sarr(j)
            end % 1. while
            
            
            if tmp < BSR532Smintrust-diffisoll % noetig falls iter > itmax.
                Btemp532S=Btemp532S./tmp.*BSR532Smintrust;
                BSRAtFit532Sarr(j) = BSRAtFit532Sarr(j) ./tmp.* BSR532Smintrust;
            end
            wo532S= find(Btemp532S < minimumBSR_cloudmask_ch532s );    %& H< hwo1);
            % ? und waeum hat er die Werte jetzt rausgesucht?            % -----------------------------------------------------------------------------------------------------
            
            %
            % 355
            condi=1; iter=0; itmax=600;
            hz355=0;
            [VoI,BiI]= minintsuche(abs(Psoll355(Sel355P(40:length(Sel355P)))-P355Klett(Sel355P(40:length(Sel355P)),j)),40);
            clearint=VoI:BiI;
            while condi
                iter = iter+1;
                if iter > itmax, condi = 0; end
                
                BSRAtFiterr = BSRAtFit355arr(j) ./ 5;
                [Beta, dBdR355, dBdLR355, dBdP355, CLidar] = klettinv_ableit4( BSRAtFit355arr(j), FitRangearr(:,j), H(Sel355P), P355Klett(Sel355P,j), P355Kletterr(Sel355P,j), ...
                    LR355arr(Sel355P,j), AlRay355(Sel355P,1), BeRa355(Sel355P,1));
                Betaaer355(Sel355P)=Beta-BeRa355(Sel355P,1);
                Betaaer355err(Sel355P,j)=abs(dBdR355.*BSRAtFiterr)+abs(dBdLR355.*LR355arrerr(Sel355P,j))+abs(dBdP355.*P355Kletterr(Sel355P,j));
                Btemp355(Sel355P)=Beta./BeRa355(Sel355P,1); Btemp355err(Sel355P)=Betaaer355err(Sel355P,j)./BeRa355(Sel355P,1);
                tmp=mymean(Btemp355(Sel355P(clearint)));
                
                [Beta2, dBdR3552, dBdLR3552, dBdP3552, CLidar2] = klettinv_ableit4( BSRAtFit355arr(j)+1, FitRangearr(:,j), H(Sel355P), P355Klett(Sel355P,j), P355Kletterr(Sel355P,j), ...
                    LR355arr(Sel355P,j), AlRay355(Sel355P,1), BeRa355(Sel355P,1));
                BetaAer355_2(Sel355P)=Beta2-BeRa355(Sel355P,1);
                %BetaAer355_2err(Sel355P,j)=abs(dBdR3552.*BSRAtFiterr)+abs(dBdLR3552.*LR355arrerr(Sel355P,j))+abs(dBdP3552.*P355Kletterr(Sel355P,j));
                Btemp355_2(Sel355P)=Beta2./BeRa355(Sel355P,1); %Btemp355_2err(Sel355P)=BetaAer355_2err(Sel355P,j)./BeRa355(Sel355P,1);
                tmp2=mymean(Btemp355_2(Sel355P(clearint)));
                
                deltasoll = BSR355mintrust - tmp;
                deltab=(tmp2-tmp);
                if abs(deltasoll) > 0.01
                    %w=(BSR355sollarr(j) - tmp) ./ deltab;
                    BSRAtFit355arr(j) = BSRAtFit355arr(j) +1./deltab.*deltasoll;
                    if BSRAtFit355arr(j) > 1e6, hz355=hz355+1; BSRAtFit355arr(j) =1e6; end
                else
                    condi=0; %disp('bringt nichts mehr'),
                end
                diffi = abs(tmp - BSR355mintrust);
                if abs(diffi) < diffisoll, condi=0;  end  % normales Ende
                if hz355 >hzlim, condi = 0; end   % Rdbeding. irrelevant
                
                % deltab
                % qq=BSRAtFit355arr(j)
            end % 1. while
            
            
            if tmp < BSR355mintrust-diffisoll% noetig falls iter > itmax.
                Btemp355=Btemp355./tmp.*BSR355mintrust;
            end
            wo355= find(Btemp355 < minimumBSR_cloudmask_ch355 );    %& H< hwo1);
            
            %--------------------------------------------------------------------------------------------------------------------------------------------------------------------
            % alleaeroposi=sort(cat(1,wo532,wo532S,wo355));
            % da=diff(alleaeroposi);
            % da2=find(da >0);
            % woaerosol=[1, alleaeroposi(da2+1)];
            % stimmt das? Wir brauchen es nicht
            
            %% cloud mask
            %wo keine Wolke
            woaerosol = find(Btemp532 < minimumBSR_cloudmask_ch532 & Btemp532S < minimumBSR_cloudmask_ch532s & Btemp355 < minimumBSR_cloudmask_ch355);
            LR532arr(woaerosol,j) = LR532_aerosol;
            LR532Sarr(woaerosol,j) = LR532s_aerosol;
            LR355arr(woaerosol,j) = LR355_aerosol;
%connrange:            calculate start and end index of connected ranges
%and sort according to size --> der groesste zusammenhaengende abschnitt wo
%die Bedingugen wahr sind. Achtung, kann auch unter einer Wolke sein. ist
%es hier sinnvoll auf ueber 2000m zu gehen weil nur da die Luftmassen
%uebereinstimmen?-------------------------------------------------------------------------------------------------------------------------------------
            guteaeroposi= connrnge(H>  UeberlappEnde & ... %hinter dem Ueberlapp
                H < hwo1 & ...vor der unteren Randbedingung
                Btemp532 < minimumBSR_cloudmask_ch532 & ... %da wo keine Wolke ist
                Btemp532S < minimumBSR_cloudmask_ch532 & ...
                Btemp355 < minimumBSR_cloudmask_ch355);
            
            if length(guteaeroposi) > 1
                guteaeroposi = (guteaeroposi(1):guteaeroposi(2));%geeingnete position fuer vergleich (kontrollrange fuer BSR355soll)
            else
                guteaeroposi = 20:40;  % irgendwelche Positionen dicht unter Flugzeug
                ichmerkmirkomischepositionen = 1; % warum aendert er nicht direkt hier das Abbruchkriterium?--------------------
            end
            
            
            
            
            
            % wir glauben, dass die Wolkenmaske und damit die Verteilung, an welchen
            % Positionen das LR f?r Aerosol oder Wolken gesetzt wurde, "richtig genug
            % ist" um die eigentliche Rechnung durchzuf?hren. Wir iterireren jetzt (mit
            % dem hoffentlich richtigem LR f?r wolke die Randbedingung so lange, bis
            % die L?sung f?r den Fall "keine dicke Wolke" stimmt.
            
            % ?
            % --------------------------------------------------------------------------------------------------------------
            BSR532haben = mymedian(Btemp532(guteaeroposi));      % war mean
            BSR532sollarr(j)=mymedian(BSR532Karlmedianvgl(guteaeroposi));
            if BSR532sollarr(j) < BSR532mintrust || ~isfinite(BSR532sollarr(j))
                BSR532sollarr(j) = BSR532sollnotfall;
                Abbruch532(j) = Abbruch532(j)+1000;
            end
            
           
            %% Second Klett iterration ========================================================================================
            % finetuning BSRatfit with adjusted LR
            %532
            condi=1; iter=0; itmax=500;
            controllBSRWert=zeros(itmax,1);
            while condi
                iter=iter+1;
                if iter >= itmax, condi=0; disp(['no convergence after ' itmax 'iterations']); end
                
                BSRAtFiterr = BSRAtFit532arr(j) ./ 5;
                [Beta, dBdR532, dBdLR532, dBdP532, CLidar] = klettinv_ableit4( BSRAtFit532arr(j), FitRangearr(:,j), H(Sel532P), P532Klett(Sel532P,j), P532Kletterr(Sel532P,j), ...
                    LR532arr(Sel532P,j), AlRay532(Sel532P,1), BeRa532(Sel532P,1));
                Betaaer532(Sel532P)=Beta-BeRa532(Sel532P,1);
                Betaaer532err(Sel532P,j)=abs(dBdR532.*BSRAtFiterr)+abs(dBdLR532.*LR532arrerr(Sel532P,j))+abs(dBdP532.*P532Kletterr(Sel532P,j));
                Btemp532(Sel532P)=Beta./BeRa532(Sel532P,1); Btemp532err(Sel532P)=Betaaer532err(Sel532P,j)./BeRa532(Sel532P,1);
                BSR532haben = mymedian(Btemp532(guteaeroposi)); % war mymean
                
                q=BSRAtFit532arr(j)+0.2;
                
                [Beta2, dBdR532, dBdLR532, dBdP532, CLidar] = klettinv_ableit4( q, FitRangearr(:,j), H(Sel532P), P532Klett(Sel532P,j), P532Kletterr(Sel532P,j), ...
                    LR532arr(Sel532P,j), AlRay532(Sel532P,1), BeRa532(Sel532P,1));
                BetaAer532_2(Sel532P)=Beta2-BeRa532(Sel532P,1);
                BetaAer532_2err(Sel532P,j)=abs(dBdR532.*BSRAtFiterr)+abs(dBdLR532.*LR532arrerr(Sel532P,j))+abs(dBdP532.*P532Kletterr(Sel532P,j));
                Btemp532_2(Sel532P)=Beta2./BeRa532(Sel532P,1); Btemp532_2err(Sel532P)=BetaAer532_2err(Sel532P,j)./BeRa532(Sel532P,1);
                BSR532haben2 = mymedian(Btemp532_2(guteaeroposi));   % war mean
                deltab=(BSR532haben2-BSR532haben);
                if abs(deltab) > 0.01
                    w=(BSR532sollarr(j) - BSR532haben) ./ deltab;   %warum ist es hier furch data ab???  !!!
                    BSRAtFit532arr(j) = BSRAtFit532arr(j) + w.*0.2;
                else
                    condi=0; %disp('bringt nichts mehr'),
                end
                diffi = abs(BSR532haben - BSR532sollarr(j));
                if abs(diffi) < diffisoll, condi=0;  end  % normales Ende
                
                controllBSRWert(iter) =  BSR532haben;
            end % while f?r die Randbedingung
            
            %sporadisch kommen zu niedrige Rd-bedingungen vor, weil vermutlich die
            %LR total falsch sind. Dies wird hier abgefangen: (gefunden bei
            %532S) welcher Rand? unten oder oben - ich meine unten
            if BSRAtFit532arr(j) < BSR532mintrust -diffisoll
                BSRAtFit532arr(j) = BSR532mintrust;
                Abbruch532(j) = Abbruch532(j)+0.03;
            end
            
            
            % 532S
            if BSR532Ssollarr(j) < BSR532Smintrust - diffisoll || ~isfinite(BSR532Ssollarr(j)) % warum wir das jetzt hier am Anfang nochmal gecheckt??? 
                BSR532Ssollarr(j) = BSR532Ssollnotfall;
                Abbruch532s(j) = Abbruch532s(j)+0.1;  % Was ist das? warum gibt es das nur bei 532S du kannst nicht ueberall 0,3 nehmen.--------------------------------------------------
                %disp(['something wrong??' string(j)])
            end
            
            condi=1; iter=0; itmax=500;
            controllBSRWert532S=zeros(itmax,1);
            while condi
                iter=iter+1;
                if iter >= itmax, condi=0; disp('trotz langer, muehsamer Suche keine Konvergenz gefunden'); end
                
                BSRAtFiterr = BSRAtFit532Sarr(j) ./ 5;
                [Beta, dBdR, dBdLR, dBdP532, CLidar] = klettinv_ableit4( BSRAtFit532Sarr(j), FitRangearr(:,j), H(Sel532S), P532SKlett(Sel532S,j), P532SKletterr(Sel532S,j), ...
                    LR532Sarr(Sel532S,j), AlRay532(Sel532S,1), BeRa532S(Sel532S,1));
                Betaaer532S(Sel532S)=Beta-BeRa532S(Sel532S,1);
                Betaaer532Serr(Sel532S,j)=abs(dBdR.*BSRAtFiterr)+abs(dBdLR.*LR532Sarrerr(Sel532S,j))+abs(dBdP532.*P532SKletterr(Sel532S,j));
                Btemp532S(Sel532S)=Beta./BeRa532S(Sel532S,1); Btemp532Serr(Sel532S)=Betaaer532Serr(Sel532S,j)./BeRa532S(Sel532S,1);
                BSR532Shaben = mymedian(Btemp532S(guteaeroposi));    % mean
                
                q=BSRAtFit532Sarr(j)+0.2;
                
                [Beta2, dBdR, dBdLR, dBdP532, CLidar] = klettinv_ableit4( q, FitRangearr(:,j), H(Sel532S), P532SKlett(Sel532S,j), P532SKletterr(Sel532S,j), ...
                    LR532Sarr(Sel532S,j), AlRay532(Sel532S,1), BeRa532S(Sel532S,1));
                Betaaer532S_2(Sel532S)=Beta2-BeRa532S(Sel532S,1);
                Betaaer532S_2err(Sel532S,j)=abs(dBdR.*BSRAtFiterr)+abs(dBdLR.*LR532Sarrerr(Sel532S,j))+abs(dBdP532.*P532SKletterr(Sel532S,j));
                Btemp532S_2(Sel532S)=Beta2./BeRa532S(Sel532S,1); Btemp532S_2err(Sel532S)=Betaaer532S_2err(Sel532S,j)./BeRa532S(Sel532S,1);
                BSR532Shaben2 = mymedian(Btemp532S_2(guteaeroposi));      % mean
                deltab=(BSR532Shaben2-BSR532Shaben);
                if abs(deltab) > 0.01
                    w=(BSR532Ssollarr(j) - BSR532Shaben) ./ deltab;
                    BSRAtFit532Sarr(j) = BSRAtFit532Sarr(j) + w.*0.2;
                    BSRAtFit532Sarr(j)
                else
                    condi=0; %disp('bringt nichts mehr'),
                end
                diffi = abs(BSR532Shaben - BSR532Ssollarr(j));
                if abs(diffi) < diffisoll, condi=0;  end  % normales Ende
                
                controllBSRWert532S(iter) =  BSR532haben;
            end % while f?r die Randbedingung
            
            %sporadisch kommen zu niedirige Rd-bedingungen vor, weil vermutlich die
            %LR total falsch sind. Dies wird hier abgefangen: (gefunden bei 532S)
            %--------------------------------- ist das hier doppelt mit
            %oben? was genau passiert da?
            if BSRAtFit532Sarr(j) < BSR532Smintrust -diffisoll
                BSRAtFit532Sarr(j) = BSR532Smintrust;
                Abbruch532s(j) = Abbruch532s(j)+0.03;
            end
            
            
            % 355
            BSR355sollarr(j)=mymedian(BSR355Karlmedianvgl(guteaeroposi));
            if BSR355sollarr(j) < BSR355mintrust -diffisoll|| ~isfinite(BSR355sollarr(j))
                BSR355sollarr(j) = BSR355sollnotfall;
                Abbruch355(j) = Abbruch355(j)+0.3;
            end
            
            
            condi=1; iter=0; itmax=500;
            controllBSRWert=zeros(itmax,1);
            while condi
                iter=iter+1;
                if iter >= itmax, condi=0; disp('no convergence 355nm'); end
                
                BSRAtFiterr = BSRAtFit355arr(j) ./ 5;
                [Beta, dBdR355, dBdLR355, dBdP355, CLidar] = klettinv_ableit4( BSRAtFit355arr(j), FitRangearr(:,j), H(Sel355P), P355Klett(Sel355P,j), P355Kletterr(Sel355P,j), ...
                    LR355arr(Sel355P,j), AlRay355(Sel355P,1), BeRa355(Sel355P,1));
                Betaaer355(Sel355P)=Beta-BeRa355(Sel355P,1);
                Betaaer355err(Sel355P,j)=abs(dBdR355.*BSRAtFiterr)+abs(dBdLR355.*LR355arrerr(Sel355P,j))+abs(dBdP355.*P355Kletterr(Sel355P,j));
                Btemp355(Sel355P)=Beta./BeRa355(Sel355P,1); Btemp355err(Sel355P)=Betaaer355err(Sel355P,j)./BeRa355(Sel355P,1);
                BSR355haben = mymedian(Btemp355(guteaeroposi)); % war mymean
                
                q=BSRAtFit355arr(j)+0.2;
                
                [Beta2, dBdR355, dBdLR355, dBdP355, CLidar] = klettinv_ableit4( q, FitRangearr(:,j), H(Sel355P), P355Klett(Sel355P,j), P355Kletterr(Sel355P,j), ...
                    LR355arr(Sel355P,j), AlRay355(Sel355P,1), BeRa355(Sel355P,1));
                BetaAer355_2(Sel355P)=Beta2-BeRa355(Sel355P,1);
                BetaAer355_2err(Sel355P,j)=abs(dBdR355.*BSRAtFiterr)+abs(dBdLR355.*LR355arrerr(Sel355P,j))+abs(dBdP355.*P355Kletterr(Sel355P,j));
                Btemp355_2(Sel355P)=Beta2./BeRa355(Sel355P,1); Btemp355_2err(Sel355P)=BetaAer355_2err(Sel355P,j)./BeRa355(Sel355P,1);
                BSR355haben2 = mymedian(Btemp355_2(guteaeroposi));   % war mean
                deltab=(BSR355haben2-BSR355haben);
                if abs(deltab) > 0.01
                    w=(BSR355sollarr(j) - BSR355haben) ./ deltab;
                    BSRAtFit355arr(j) = BSRAtFit355arr(j) + w.*0.2;
                else
                    condi=0; %disp('bringt nichts mehr'),
                end
                diffi = abs(BSR355haben - BSR355sollarr(j));
                if abs(diffi) < diffisoll, condi=0;  end  % normales Ende
                
                controllBSRWert(iter) =  BSR355haben;
            end % while f?r die Randbedingung
            
            %sporadisch kommen zu niedirige Rd-bedingungen vor, weil vermutlich die
            %LR total falsch sind. Dies wird hier abgefangen:
            if BSRAtFit355arr(j) < BSR355mintrust -diffisoll
                BSRAtFit355arr(j) = BSR355mintrust;
                Abbruch355(j) = Abbruch355(j)+0.03;
            end
            
            
            % Das ist jetzt der Casus Knacktus, Iteration des LR
            % wahrscheinlich ist beta immer noch zu klein, denn bei dicken Wolken
            % hat der Wert BSRATFit keinen Einflu? auf die L?sung
            % Das bedeutet, die einzige Chance, eine realistische L?sung zu
            % bekommen besteht darin, iterativ das LR in der Wolke solange
            % anzupassen, bis die L?sung stimmt. Dies geschieht hier
            %% second cloudmask
            % wir passen vor der finalen Iteration die Wolkenmaske noch einmal an
            % wowolke = find(Btemp532 > minimumBSR_cloudmask_ch532 | Btemp532S > minimumBSR_cloudmask_ch532s | Btemp355 > minimumBSR_cloudmask_ch355); % ich bin mir nicht sicher ob das hier geschickt gewaehlt ist. 
            wowolke = find(Btemp532 > minimumBSR_cloudmask_ch532 |  Btemp355 > minimumBSR_cloudmask_ch355);
            %if ~isempty(wowolke)% sonst ja sinnlos                
                %woaerosol = find(Btemp532 <= minimumBSR_cloudmask_ch532 & Btemp532S <= minimumBSR_cloudmask_ch532s & Btemp355 <= minimumBSR_cloudmask_ch355);
                woaerosol = ~wowolke;
                LR532arr(wowolke,j)= LR532_wolke;
                LR532arr(woaerosol,j)= LR532_aerosol;
                LR532Sarr(wowolke,j)= LR532s_wolke;
                LR532Sarr(woaerosol,j)= LR532s_aerosol;
                LR355arr(wowolke,j)= LR355_wolke;
                LR355arr(woaerosol,j)= LR355_aerosol;
                
                %% third Klett ==============================================================================================
                %neuer klett mit aktualisierter Wolkenmaske und LR anpassung in der Wolke
                %
                
                % 532P
                condi=1; iter=0; itmax=500;
                hz532=0; tz532=0;  % hz532 / tz532 Zaehler fuer hohe - tiefe Werte
                gut = 3; % Prozent-Abweichung wie gut mirt BSR an BSR532soll kommen
                refer=zeros(itmax,1);  refer2=zeros(itmax,1);
                while condi
                    iter = iter+1;
                    if iter ==1, bininlrschleife532(j) = 1; end
                    if iter > 500, condi=0; disp('keine Konvergenz 532!'); Abbruch532(j)=Abbruch532(j)+4;   end
                    
                    [Beta, dBdR532, dBdLR532, dBdP532, CLidar532] = klettinv_ableit4( BSRAtFit532arr(j), FitRangearr(:,j), H(Sel532P), P532Klett(Sel532P,j), P532Kletterr(Sel532P,j), ...
                        LR532arr(Sel532P,j), AlRay532(Sel532P,1), BeRa532(Sel532P,1));
                    Betaaer532(Sel532P)=Beta-BeRa532(Sel532P,1);
                    Betaaer532err(Sel532P,j)=abs(dBdR532.*BSRAtFiterr)+abs(dBdLR532.*LR532arrerr(Sel532P,j))+abs(dBdP532.*P532Kletterr(Sel532P,j));
                    Btemp532(Sel532P)=Beta./BeRa532(Sel532P,1); Btemp532err(Sel532P)=Betaaer532err(Sel532P,j)./BeRa532(Sel532P,1);
                    BSR532haben = mymedian(Btemp532(guteaeroposi));      %% war mean
                    
                    LRtest=LR532arr(:,j); LRtest(wowolke)=LRtest(wowolke)+1;
                    
                    [Beta2, dB2dR, dB2dLR, dB2dP, CLidar2] = klettinv_ableit4( BSRAtFit532arr(j), FitRangearr(:,j), H(Sel532P), P532Klett(Sel532P,j), P532Kletterr(Sel532P,j), ...
                        LRtest(Sel532P), AlRay532(Sel532P,1), BeRa532(Sel532P,1));
                    BetaAer532_2(Sel532P)=Beta2-BeRa532(Sel532P,1);
                    BetaAer532_2err(Sel532P,j)=abs(dB2dR.*BSRAtFiterr)+abs(dB2dLR.*LR532arrerr(Sel532P,j))+abs(dB2dP.*P532Kletterr(Sel532P,j));
                    Btemp532_2(Sel532P)=Beta2./BeRa532(Sel532P,1); Btemp532_2err(Sel532P)=BetaAer532_2err(Sel532P,j)./BeRa532(Sel532P,1);
                    BSR532haben2 = mymedian(Btemp532_2(guteaeroposi));    % mean
                    
                    refer(iter) = BSR532haben;
                    refer2(iter) = BSR532haben2;
                    dxdlr = refer2(iter)-refer(iter);
                    diffi = BSR532sollarr(j) - refer(iter);
                    deltax=diffi./dxdlr;
                    
                    
                    if refer(iter) ./ BSR532sollarr(j) > 1+gut ./ 100          % BSR zu gro?
                        LR532arr(wowolke,j) = LR532arr(wowolke,j) +deltax;     %passe LR an
                        if mymean(LR532arr(wowolke,j)) > LR532_upperlimit
                            LR532arr(wowolke,j) = LR532_upperlimit; hz532=hz532+1;
                            if (BSRAtFit532arr(j) > 2 && hz532 < hzlim), BSRAtFit532arr(j) = BSRAtFit532arr(j)./1.1; end
                        end
                        if mymean(LR532arr(wowolke,j)) < LR532_lowerlimit
                            LR532arr(wowolke,j) = 5; tz532=tz532+1;
                            if (BSRAtFit532arr(j) < 1e6 && tz532 < tzlim), BSRAtFit532arr(j) = BSRAtFit532arr(j).*1.1; end
                        end
                    elseif refer(iter) ./ BSR532sollarr(j) < 1-gut ./ 100      % BSR zu klein
                        LR532arr(wowolke,j) = LR532arr(wowolke,j) +deltax;     % passe LR an
                        if mymean(LR532arr(wowolke,j)) > LR532_upperlimit
                            LR532arr(wowolke,j) = LR532_upperlimit; hz532=hz532+1;
                            if (BSRAtFit532arr(j) > 2 && hz532 < hzlim), BSRAtFit532arr(j) = BSRAtFit532arr(j)./1.1; end
                        end
                        if mymean(LR532arr(wowolke,j)) < LR532_lowerlimit
                            LR532arr(wowolke,j) = 5; tz532=tz532+1;
                            if (BSRAtFit532arr(j) < 1e6 && tz532 < tzlim), BSRAtFit532arr(j) = BSRAtFit532arr(j).*1.1; end
                        end
                    else
                        condi=0; Abbruch532(j)=Abbruch532(j)+1;  % das sch?ne Ende
                    end
                    
                    
                    if hz532>=hzlim, condi = 0; Abbruch532(j)=Abbruch532(j)+3;  end      % disp('hz > 3'); i, end
                    if tz532>=tzlim, condi = 0; Abbruch532(j)=Abbruch532(j)+2;  end      % disp('tz > 3'); i, end
                    
                end    % while des LR
                
                
                % 532S (LR Iter)
                condi=1; iter=0; itmax=500;
                hz532S=0; tz532S=0;  % hz532S / tz532S Zaehler fuer hohe - tiefe Werte
                gut = 3; % Prozent-Abweichung wie gut mirt BSR an BSR532Ssoll kommen
                refer=zeros(itmax,1);  refer2=zeros(itmax,1);
                while condi
                    iter = iter+1;
                    if iter ==1, bininlrschleife532S(j) = 1; end
                    if iter > 500, condi=0; disp('keine Konvergenz 532S!'); Abbruch532s(j)=Abbruch532s(j)+4;   end
                    
                    [Beta, dBdR532S, dBdLR532s, dBdP532S, CLidar532S] = klettinv_ableit4( BSRAtFit532Sarr(j), FitRangearr(:,j), H(Sel532S), P532SKlett(Sel532S,j), P532SKletterr(Sel532S,j), ...
                        LR532Sarr(Sel532S,j), AlRay532(Sel532S,1), BeRa532S(Sel532S,1));
                    Betaaer532S(Sel532S)=Beta-BeRa532S(Sel532S,1);
                    Betaaer532Serr(Sel532S,j)=abs(dBdR532S.*BSRAtFiterr)+abs(dBdLR532s .*LR532Sarrerr(Sel532S,j))+abs(dBdP532S.*P532SKletterr(Sel532S,j));
                    Btemp532S(Sel532S)=Beta./BeRa532S(Sel532S,1); Btemp532Serr(Sel532S)=Betaaer532Serr(Sel532S,j)./BeRa532S(Sel532S,1);
                    BSR532Shaben = mymedian(Btemp532S(guteaeroposi));      %% war mean
                    
                    LRtest=LR532Sarr(:,j); LRtest(wowolke)=LRtest(wowolke)+1;
                    
                    [Beta2, dB532S2dR, dB532S2dLR, dB532S2dP, CLidar2] = klettinv_ableit4( BSRAtFit532Sarr(j), FitRangearr(:,j), H(Sel532S), P532SKlett(Sel532S,j), P532SKletterr(Sel532S,j), ...
                        LRtest(Sel532S), AlRay532(Sel532S,1), BeRa532S(Sel532S,1));
                    BetaAer532S_2(Sel532S)=Beta2-BeRa532S(Sel532S,1);
                    BetaAer532S_2err(Sel532S,j)=abs(dB532S2dR.*BSRAtFiterr)+abs(dB532S2dLR.*LR532Sarrerr(Sel532S,j))+abs(dB532S2dP.*P532SKletterr(Sel532S,j));
                    Btemp532S_2(Sel532S)=Beta2./BeRa532S(Sel532S,1); Btemp532S_2err(Sel532S)=BetaAer532S_2err(Sel532S,j)./BeRa532S(Sel532S,1);
                    BSR532Shaben2 = mymedian(Btemp532S_2(guteaeroposi));    % mean
                    
                    refer(iter) = BSR532Shaben;
                    refer2(iter) = BSR532Shaben2;
                    dxdlr = refer2(iter)-refer(iter);
                    diffi = BSR532Ssollarr(j) - refer(iter);
                    deltax=diffi./dxdlr;
                    
                    
                    if refer(iter) ./ BSR532Ssollarr(j) > 1+gut ./ 100          % BSR zu gro?
                        LR532Sarr(wowolke,j) = LR532Sarr(wowolke,j) +deltax;
                        if mymean(LR532Sarr(wowolke,j)) > LR532_upperlimit
                            LR532Sarr(wowolke,j) = LR532_upperlimit; hz532S=hz532S+1;
                            if (BSRAtFit532Sarr(j) > 2 && hz532S < hzlim), BSRAtFit532Sarr(j) = BSRAtFit532Sarr(j)./1.1; end
                        end
                        if mymean(LR532Sarr(wowolke,j)) < LR532_lowerlimit
                            LR532Sarr(wowolke,j) = 5; tz532S=tz532S+1;
                            if (BSRAtFit532Sarr(j) < 1e6 && tz532S < tzlim), BSRAtFit532Sarr(j) = BSRAtFit532Sarr(j).*1.1; end
                        end
                    elseif refer(iter) ./ BSR532Ssollarr(j) < 1-gut ./ 100     % BSR zu klein
                        LR532Sarr(wowolke,j) = LR532Sarr(wowolke,j) +deltax;
                        if mymean(LR532Sarr(wowolke,j)) > LR532_upperlimit
                            LR532Sarr(wowolke,j) = LR532_upperlimit; hz532S=hz532S+1;
                            if (BSRAtFit532Sarr(j) > 2 && hz532S < hzlim), BSRAtFit532Sarr(j) = BSRAtFit532Sarr(j)./1.1; end
                        end
                        if mymean(LR532Sarr(wowolke,j)) < LR532_lowerlimit
                            LR532Sarr(wowolke,j) = 5; tz532S=tz532S+1;
                            if (BSRAtFit532Sarr(j) < 1e6 && tz532S < tzlim), BSRAtFit532Sarr(j) = BSRAtFit532Sarr(j).*1.1; end
                        end
                    else
                        condi=0; Abbruch532s(j)=Abbruch532s(j)+1;  % das sch?ne Ende
                    end
                    
                    if hz532S>=hzlim, condi = 0; Abbruch532s(j)=Abbruch532s(j)+3;  end      % disp('hz > 3'); i, end
                    if tz532S>=tzlim, condi = 0; Abbruch532s(j)=Abbruch532s(j)+2;  end      % disp('tz > 3'); i, end
                    
                end    % while des LR
                
                
                % 355 (LR Iter)
                
                condi=1; iter=0; itmax=500;
                hz355=0; tz355=0;  % hz355 / tz355 Zaehler fuer hohe - tiefe Werte
                gut = 3; % Prozent-Abweichung wie gut mirt BSR an BSR355soll kommen
                refer=zeros(itmax,1);  refer2=zeros(itmax,1);
                while condi
                    iter = iter+1;
                    if iter ==1, bininlrschleife355(j) = 1; end
                    if iter > 500, condi=0; disp('keine Konvergenz 355!'); Abbruch355(j)=Abbruch355(j)+4;   end
                    
                    [Beta, dBdR355, dBdLR355, dBdP355, CLidar355] = klettinv_ableit4( BSRAtFit355arr(j), FitRangearr(:,j), H(Sel355P), P355Klett(Sel355P,j), P355Kletterr(Sel355P,j), ...
                        LR355arr(Sel355P,j), AlRay355(Sel355P,1), BeRa355(Sel355P,1));
                    Betaaer355(Sel355P)=Beta-BeRa355(Sel355P,1);
                    Betaaer355err(Sel355P,j)=abs(dBdR355.*BSRAtFiterr)+abs(dBdLR355.*LR355arrerr(Sel355P,j))+abs(dBdP355.*P355Kletterr(Sel355P,j));
                    Btemp355(Sel355P)=Beta./BeRa355(Sel355P,1); Btemp355err(Sel355P)=Betaaer355err(Sel355P,j)./BeRa355(Sel355P,1);
                    BSR355haben = mymedian(Btemp355(guteaeroposi));      %% war mean
                    
                    LRtest=LR355arr(:,j); LRtest(wowolke)=LRtest(wowolke)+1;
                    
                    [Beta2, dB2dR, dB2dLR, dB2dP, CLidar2] = klettinv_ableit4( BSRAtFit355arr(j), FitRangearr(:,j), H(Sel355P), P355Klett(Sel355P,j), P355Kletterr(Sel355P,j), ...
                        LRtest(Sel355P), AlRay355(Sel355P,1), BeRa355(Sel355P,1));
                    BetaAer355_2(Sel355P)=Beta2-BeRa355(Sel355P,1);
                    BetaAer355_2err(Sel355P,j)=abs(dB2dR.*BSRAtFiterr)+abs(dB2dLR.*LR355arrerr(Sel355P,j))+abs(dB2dP.*P355Kletterr(Sel355P,j));
                    Btemp355_2(Sel355P)=Beta2./BeRa355(Sel355P,1); Btemp355_2err(Sel355P)=BetaAer355_2err(Sel355P,j)./BeRa355(Sel355P,1);
                    BSR355haben2 = mymedian(Btemp355_2(guteaeroposi));    % mean
                    
                    refer(iter) = BSR355haben;
                    refer2(iter) = BSR355haben2;
                    dxdlr = refer2(iter)-refer(iter);
                    diffi = BSR355sollarr(j) - refer(iter);
                    deltax=diffi./dxdlr;
                    
                    
                    if refer(iter) ./ BSR355sollarr(j) > 1+gut ./ 100         % BSR zu gro?
                        LR355arr(wowolke,j) = LR355arr(wowolke,j) +deltax;
                        if mymean(LR355arr(wowolke,j)) > LR532_upperlimit
                            LR355arr(wowolke,j) = LR532_upperlimit; hz355=hz355+1;
                            if (BSRAtFit355arr(j) > 2 && hz355 < hzlim), BSRAtFit355arr(j) = BSRAtFit355arr(j)./1.1; end
                        end
                        if mymean(LR355arr(wowolke,j)) < LR532_lowerlimit
                            LR355arr(wowolke,j) = 5; tz355=tz355+1;
                            if (BSRAtFit355arr(j) < 1e6 && tz355 < tzlim), BSRAtFit355arr(j) = BSRAtFit355arr(j).*1.1; end
                        end
                    elseif refer(iter) ./ BSR355sollarr(j) < 1-gut ./ 100      % BSR zu klein
                        LR355arr(wowolke,j) = LR355arr(wowolke,j) +deltax;
                        if mymean(LR355arr(wowolke,j)) > LR532_upperlimit
                            LR355arr(wowolke,j) = LR532_upperlimit; hz355=hz355+1;
                            if (BSRAtFit355arr(j) > 2 && hz355 < hzlim), BSRAtFit355arr(j) = BSRAtFit355arr(j)./1.1; end
                        end
                        if mymean(LR355arr(wowolke,j)) < LR532_lowerlimit
                            LR355arr(wowolke,j) = 5; tz355=tz355+1;
                            if (BSRAtFit355arr(j) < 1e6 && tz355 < tzlim), BSRAtFit355arr(j) = BSRAtFit355arr(j).*1.1; end
                        end
                    else
                        condi=0; Abbruch355(j)=Abbruch355(j)+1;  % das sch?ne Ende
                    end
                    
                    
                    if hz355>=hzlim, condi = 0; Abbruch355(j)=Abbruch355(j)+3;  end      % disp('hz > 3'); i, end
                    if tz355>=tzlim, condi = 0; Abbruch355(j)=Abbruch355(j)+2;  end      % disp('tz > 3'); i, end
                    
                end    % while des LR
                
                
                
            %end % if wowolke nicht leer
            
            %was ist das hier?
            if (ichmerkmirkomischepositionen ~=0)
                Abbruch532(j)=Abbruch532(j)+100;
                Abbruch532s(j)=Abbruch532s(j)+100;
                Abbruch355(j)=Abbruch355(j)+100;
            end
            
            % Wir reduzieren die Fehlerabschaetzung fuer Betaaer des LR (LR532_errorestimate) wenn Abbruch = 1 ist
            % warum?
            if Abbruch532(j) ==1
                LR532arrerr(wowolke,j) = 1;
                Betaaer532err(Sel532P,j)=abs(dBdR532.*BSRAtFiterr)+abs(dBdLR532.*LR532arrerr(Sel532P,j))+abs(dBdP532.*P532Kletterr(Sel532P,j));
            end
            
            if Abbruch532s(j) ==1
                LR532Sarrerr(wowolke,j)=1;
                Betaaer532Serr(Sel532S,j)=abs(dBdR532S.*BSRAtFiterr)+abs(dBdLR532s.*LR532Sarrerr(Sel532S,j))+abs(dBdP532S.*P532SKletterr(Sel532S,j));
            end
            
            
            if Abbruch355(j) ==1
                LR355arrerr(wowolke,j)=1;
                Betaaer355err(Sel355P,j)=abs(dBdR355.*BSRAtFiterr)+abs(dBdLR355.*LR355arrerr(Sel355P,j))+abs(dBdP355.*P355Kletterr(Sel355P,j));
            end
            
            
     
            
            
            %% speichern des Zeitschrittes:
            
            BSR532Klett(Sel532P,j)=Btemp532(Sel532P); BSR532Kletterr(Sel532P,j)=Btemp532err(Sel532P);
            BetaAer532Klett(Sel532P,j)=Betaaer532(Sel532P); BetaAer532Kletterr(Sel532P,j)=Betaaer532err(Sel532P,j);
            %attenu532P(Sel532P,j) = P532Klett(Sel532P,j).*H(Sel532P).^2 ./ CLidar532(Sel532P(1));
            %attenu532Perr(Sel532P,j) = abs(P532Kletterr(Sel532P,j).*H(Sel532P).^2 ./ CLidar532(Sel532P(1))) + abs(attenu532P(Sel532P,j) ./ CLidar532(Sel532P(1)).*0.1.*CLidar532(Sel532P(1)));
            dBeta532dP(Sel532P,j)=dBdP532;
            dBeta532dR(Sel532P,j)=dBdR532;
            dBeta532dLR(Sel532P,j)=dBdLR532;
            %C532Lidar(Sel532P,j) =CLidar532;
            AlphaAer532(:,j)=BetaAer532Klett(:,j).*LR532arr(:,j);
            AlphaAer532err(:,j)= abs(BetaAer532Kletterr(:,j).*LR532arr(:,j)) + abs(BetaAer532Klett(:,j).*LR532arrerr(:,j));
            
            BSR532SKlett(Sel532S,j)=Btemp532S(Sel532S); BSR532SKletterr(Sel532S,j)=Btemp532Serr(Sel532S);
            BetaAer532SKlett(Sel532S,j)=Betaaer532S(Sel532S); BetaAer532SKletterr(Sel532S,j)=Betaaer532Serr(Sel532S,j);
            %attenu532S(Sel532S,j) = P532SKlett(Sel532S,j).*H(Sel532S).^2 ./ CLidar532S(Sel532S(1));
            %attenu532Serr(Sel532S,j) = abs(P532SKletterr(Sel532S,j).*H(Sel532S).^2 ./ CLidar532S(Sel532S(1))) + abs(attenu532S(Sel532S,j) ./ CLidar532S(Sel532S(1)).*0.1.*CLidar532S(Sel532S(1)));
            dBeta532SdP(Sel532S,j)=dBdP532S;
            dBeta532SdR(Sel532S,j)=dBdR532S;
            dBeta532SdLR(Sel532S,j)=dBdLR532s;
            %C532SLidar(Sel532S,j) =CLidar532S;
            AlphaAer532S(:,j)=BetaAer532SKlett(:,j).*LR532Sarr(:,j);
            AlphaAer532Serr(:,j)= abs(BetaAer532SKletterr(:,j).*LR532Sarr(:,j)) + abs(BetaAer532SKlett(:,j).*LR532Sarrerr(:,j));
            
            BSR355Klett(Sel355P,j)=Btemp355(Sel355P); BSR355Kletterr(Sel355P,j)=Btemp355err(Sel355P);
            BetaAer355Klett(Sel355P,j)=Betaaer355(Sel355P); BetaAer355Kletterr(Sel355P,j)=Betaaer355err(Sel355P,j);
            %attenu355P(Sel355P,j) = P355Klett(Sel355P,j).*H(Sel355P).^2 ./ CLidar355(Sel355P(1));
            %attenu355Perr(Sel355P,j) = abs(P355Kletterr(Sel355P,j).*H(Sel355P).^2 ./ CLidar355(Sel355P(1))) + abs(attenu355P(Sel355P,j) ./ CLidar355(Sel355P(1)).*0.1.*CLidar355(Sel355P(1)));
            dBeta355dP(Sel355P,j)=dBdP355;
            dBeta355dR(Sel355P,j)=dBdR355;
            dBeta355dLR(Sel355P,j)=dBdLR355;
            %C355Lidar(Sel355P,j) =CLidar355;
            AlphaAer355(:,j)=BetaAer355Klett(:,j).*LR355arr(:,j);
            AlphaAer355err(:,j)= abs(BetaAer355Kletterr(:,j).*LR355arr(:,j)) + abs(BetaAer355Klett(:,j).*LR355arrerr(:,j));
            
            
            
            
            
            Wolkenmaske(wowolke,j) = 1;
            
            
            
            %%
            % egal ob Wolke oder nicht - jetzt rechnen wir nochmal mit LR532_wolke und
            % der Rd-beding, die ggf. gefunden wurde f?r die "fest" L?sungen
            % aber warum??? -----------------------------------------------
            
            
%             LRfest = ones(size(LR532arr)).*LR532_wolke;
%             [Beta, dBdR532, dBdLR532, dBdP532, CLidar] = klettinv_ableit4( BSRAtFit532arr(j), FitRangearr(:,j), H(Sel532P), P532Klett(Sel532P,j), P532Kletterr(Sel532P,j), ...
%                 LRfest(Sel532P,j), AlRay532(Sel532P,1), BeRa532(Sel532P,1));
%             Betaaer532(Sel532P)=Beta-BeRa532(Sel532P,1);
%             Betaaer532err(Sel532P,1)=abs(dBdR532.*BSRAtFiterr)+abs(dBdLR532.*LR532arrerr(Sel532P,j))+abs(dBdP532.*P532Kletterr(Sel532P,j));
%             Btemp532(Sel532P)=Beta./BeRa532(Sel532P,1); Btemp532err(Sel532P)=Betaaer532err(Sel532P,1)./BeRa532(Sel532P,1);
%             BSR532Klettfest(Sel532P,j)=Btemp532(Sel532P); BSR532Klettfesterr(Sel532P,j)=Btemp532err(Sel532P);
%             BetaAer532Klettfest(Sel532P,j)=Betaaer532(Sel532P); BetaAer532Klettfesterr(Sel532P,j)=Betaaer532err(Sel532P,1);
%             
%             LRfest = ones(size(LR532Sarr)).*LR532_wolke;
%             [Beta, dBdR, dBdLR, dBdP, CLidar] = klettinv_ableit4( BSRAtFit532arr(j), FitRangearr(:,j), H(Sel532S), P532SKlett(Sel532S,j), P532SKletterr(Sel532S,j), ...
%                 LRfest(Sel532S,j), AlRay532(Sel532S,1), BeRa532S(Sel532S,1));
%             Betaaer(Sel532S)=Beta-BeRa532S(Sel532S,1);
%             Betaaererr(Sel532S,1)=abs(dBdR.*BSRAtFiterr)+abs(dBdLR.*LR532Sarrerr(Sel532S,j))+abs(dBdP.*P532Kletterr(Sel532S,j));
%             Btemp(Sel532S)=Beta./BeRa532S(Sel532S,1); Btemperr(Sel532S)=Betaaererr(Sel532S,1)./BeRa532S(Sel532S,1);
%             BSR532SKlettfest(Sel532S,j)=Btemp(Sel532S); BSR532SKlettfesterr(Sel532S,j)=Btemperr(Sel532S);
%             BetaAer532SKlettfest(Sel532S,j)=Betaaer(Sel532S); BetaAer532SKlettfesterr(Sel532S,j)=Betaaererr(Sel532S,1);
%             
%             
%             LRfest = ones(size(LR355arr)).*LR355_wolke;
%             [Beta, dBdR, dBdLR, dBdP, CLidar] = klettinv_ableit4( BSRAtFit355arr(j), FitRangearr(:,j), H(Sel355P), P355Klett(Sel355P,j), P355Kletterr(Sel355P,j), ...
%                 LRfest(Sel355P,j), AlRay355(Sel355P,1), BeRa355(Sel355P,1));
%             Betaaer(Sel355P)=Beta-BeRa355(Sel355P,1);
%             Betaaererr(Sel355P,1)=abs(dBdR.*BSRAtFiterr)+abs(dBdLR.*LR355arrerr(Sel355P,j))+abs(dBdP.*P355Kletterr(Sel355P,j));
%             Btemp(Sel355P)=Beta./BeRa355(Sel355P,1); Btemperr(Sel355P)=Betaaererr(Sel355P,1)./BeRa355(Sel355P,1);
%             BSR355Klettfest(Sel355P,j)=Btemp(Sel355P); BSR355Klettfesterr(Sel355P,j)=Btemperr(Sel355P);
%             BetaAer355Klettfest(Sel355P,j)=Betaaer(Sel355P); BetaAer355Klettfesterr(Sel355P,j)=Betaaererr(Sel355P,1);
%             
%             
%             % und jetzt rechnen wir noch einmal 532S mit dem Lidarverhaltnis aus LR532P
%             % dies gibt die "ausP" Loesungen
%             
%             
%             [Beta, dBdR, dBdLR, dBdP, CLidar] = klettinv_ableit4( BSRAtFit532Sarr(j), FitRangearr(:,j), H(Sel532S), P532SKlett(Sel532S,j), P532SKletterr(Sel532S,j), ...
%                 LR532arr(Sel532S,j), AlRay532(Sel532S,1), BeRa532S(Sel532S,1));
%             Betaaer(Sel532S)=Beta-BeRa532S(Sel532S,1);
%             Betaaererr(Sel532S,1)=abs(dBdR.*BSRAtFiterr)+abs(dBdLR.*LR532arrerr(Sel532S,j))+abs(dBdP.*P532SKletterr(Sel532S,j));
%             Btemp(Sel532S)=Beta./BeRa532S(Sel532S,1); Btemperr(Sel532S)=Betaaererr(Sel532S,1)./BeRa532S(Sel532S,1);
%             BSR532SKlettausP(Sel532S,j)=Btemp(Sel532S); BSR532SKlettausPerr(Sel532S,j)=Btemperr(Sel532S);
%             BetaAer532SKlettausP(Sel532S,j)=Betaaer(Sel532S); BetaAer532SKlettausPerr(Sel532S,j)=Betaaererr(Sel532S,1);
%             
%             
%             
        end % for Zeitschritte "entries"
        
        
        
        % was soll das hier?
%         P532roh=P532A';
%         P532Sroh=P532SA';
%         P355roh=P355A';
        
        %% finales speichern
        
%         speichern532p=['P532Klett P532Kletterr P532A BSRAtFit532arr LR532arr BetaAer532Klett BetaAer532Kletterr ' ...
%             'AlphaAer532 AlphaAer532err BSR532Klett BSR532Kletterr BetaAer532Klettfest BetaAer532Klettfesterr BSR532Klettfest ' ...
%             'BSR532Klettfesterr dBeta532dP  dBeta532dR dBeta532dLR Abbruch532 P532Abackground'];
%         
%         speichern532s=['P532SKlett P532SKletterr P532SA BSRAtFit532Sarr LR532Sarr BetaAer532SKlett BetaAer532SKletterr ' ...
%             'AlphaAer532S AlphaAer532Serr BSR532SKlett BSR532SKletterr BSR532SKlettfest BSR532SKlettfesterr BetaAer532SKlettfest ' ...
%             'BetaAer532SKlettfesterr dBeta532SdP  dBeta532SdR dBeta532SdLR Abbruch532s P532SAbackground BetaAer532SKlettausP BSR532SKlettausP'];
%         
%         
%         speichern355p=['P355Klett P355Kletterr P355A BSRAtFit355arr  LR355arr BetaAer355Klett BetaAer355Kletterr ' ...
%             'AlphaAer355 AlphaAer355err BSR355Klett BSR355Kletterr BSR355Klettfest BSR355Klettfesterr BetaAer355Klettfest ' ...
%             'BetaAer355Klettfesterr dBeta355dP  dBeta355dR dBeta355dLR Abbruch355 P355Abackground'];
%         
%         % sonstiges = [' H matlabzeit Wolkenmaske FitRangearr BSR532sollarr BSR355sollarr BSRAtFit532start BSRAtFit355start VolDep532' ];
%         sonstiges = [' H matlabzeit Wolkenmaske FitRangearr BSR532sollarr BSR355sollarr BSRAtFit532start BSRAtFit355start' ];
%         
%         liste=[speichern532p ' ' speichern532s ' ' speichern355p sonstiges];
%         
%         speichern =['save ' speicherdir Speichernamepraefix filename ' ' liste];
%         
%         eval(speichern)
        
 
        
      %entfernt: analog werte,   
      %ist hintergrund von P schon abgezogen? 
                speichern532p=['P532Klett P532Kletterr BSRAtFit532arr LR532arr BetaAer532Klett BetaAer532Kletterr ' ...
            'AlphaAer532 AlphaAer532err BSR532Klett BSR532Kletterr dBeta532dP  dBeta532dR dBeta532dLR Abbruch532 P532Abackground'];
        
        speichern532s=['P532SKlett P532SKletterr BSRAtFit532Sarr LR532Sarr BetaAer532SKlett BetaAer532SKletterr ' ...
            'AlphaAer532S AlphaAer532Serr BSR532SKlett BSR532SKletterr dBeta532SdP  dBeta532SdR dBeta532SdLR Abbruch532s P532SAbackground BetaAer532SKlettausP BSR532SKlettausP'];
        
        
        speichern355p=['P355Klett P355Kletterr BSRAtFit355arr  LR355arr BetaAer355Klett BetaAer355Kletterr ' ...
            'AlphaAer355 AlphaAer355err BSR355Klett BSR355Kletterr dBeta355dP  dBeta355dR dBeta355dLR Abbruch355 P355Abackground'];
        
        % sonstiges = [' H matlabzeit Wolkenmaske FitRangearr BSR532sollarr BSR355sollarr BSRAtFit532start BSRAtFit355start VolDep532' ];
        sonstiges = [' H matlabzeit Wolkenmaske FitRangearr BSR532sollarr BSR355sollarr BSRAtFit532start BSRAtFit355start' ];
        
        liste=[speichern532p ' ' speichern532s ' ' speichern355p sonstiges];
        
        speichern =['save ' speicherdir Speichernamepraefix '_short' filename ' ' liste];
        
        eval(speichern)
    end % for alle Daten eines Tages
    
end % if files nicht leer




return


       %koennne wir das nicht einfach einfach als nc-files abspeichern? --> Pavel
