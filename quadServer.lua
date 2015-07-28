CLIENT_EXECUTABLE = '/Users/empire/Documents/MATLAB/vrepMatlab/quadClient.m'

if (sim_call_type==sim_childscriptcall_initialization) then 
	
-- Server-side Init-------------------------------------------------------------------------
	-- Add a banner:
	black={0,0,0,0,0,0,0,0,0,0,0,0}
	purple={0,0,0,0,0,0,0,0,0,1,0,1}
	-- simAddBanner("I am controlled via the Remote Api! ('quadClient' controlls me)",0,sim_banner_bitmapfont+sim_banner_overlay,nil,simGetObjectAssociatedWithScript(sim_handle_self),black,purple)

	-- Choose a port that is probably not used (try to always use a similar code):
	simSetThreadAutomaticSwitch(false)
	local portNb=simGetIntegerParameter(sim_intparam_server_port_next)
	local portStart=simGetIntegerParameter(sim_intparam_server_port_start)
	local portRange=simGetIntegerParameter(sim_intparam_server_port_range)
	local newPortNb=portNb+1
	if (newPortNb>=portStart+portRange) then
		newPortNb=portStart
	end
	simSetIntegerParameter(sim_intparam_server_port_next,newPortNb)
	simSetThreadAutomaticSwitch(true)

	-- Check what OS we are using:
	platf=simGetIntegerParameter(sim_intparam_platform)
	if (platf==0) then
		pluginFile='v_repExtRemoteApi.dll'
	end
	if (platf==1) then
		pluginFile='libv_repExtRemoteApi.dylib'
	end
	if (platf==2) then
		pluginFile='libv_repExtRemoteApi.so'
	end

	-- Check if the required remote Api plugin is there:
	moduleName=0
	moduleVersion=0
	index=0
	pluginNotFound=true
	while moduleName do
		moduleName,moduleVersion=simGetModuleName(index)
		if (moduleName=='RemoteApi') then
			pluginNotFound=false
		end
		index=index+1
	end

	if (pluginNotFound) then
		-- Plugin was not found
		simDisplayDialog('Error',"Remote Api plugin was not found. ('"..pluginFile.."')&&nSimulation will not run properly",sim_dlgstyle_ok,true,nil,{0.8,0,0,0,0,0},{0.5,0,0,1,1,1})
	else
		-- Ok, we found the plugin.
		-- We first start the remote Api server service (this requires the v_repExtRemoteApi plugin):
		print(portNb)
		simExtRemoteApiStart(portNb) -- this server function will automatically close again at simulation end
		-- Now we start the client application:
		--result=simLaunchExecutable('CLIENT_EXECUTABLE',portNb.." "..prop1.." "..prop2.." "..prop3.."  "..prop4.."  "..noseSensor,0) -- set the last argument to 1 to see the console of the launched client
        --result = simLaunchExecutable(CLIENT_EXECUTABLE, portNb, 0)
        --print(result)

		--if (result == -1) then
               -- The executable could not be launched!
		--	simDisplayDialog('Error',"'quadClient' could not be launched. &&nSimulation will not run properly",sim_dlgstyle_ok,true,nil,{0.8,0,0,0,0,0},{0.5,0,0,1,1,1})
		--end
end
	-------------------------------------------------------------------------------------------------------------------

	-- Make sure we have version 2.4.13 or above (the particles are not supported otherwise)
	v=simGetIntegerParameter(sim_intparam_program_version)
	if (v<20413) then
		simDisplayDialog('Warning','The propeller model is only fully supported from V-REP version 2.4.13 and above.&&nThis simulation will not run as expected!',sim_dlgstyle_ok,false,'',nil,{0.8,0,0,0,0,0})
	end

	-- Detatch the manipulation sphere:
	targetObj=simGetObjectHandle('Quadricopter_target')
	simSetObjectParent(targetObj,-1,true)

	-- This control algo was quickly written and is dirty and not optimal. It just serves as a SIMPLE example

	d=simGetObjectHandle('Quadricopter_base')

	particlesAreVisible=simGetScriptSimulationParameter(sim_handle_self,'particlesAreVisible')
	simSetScriptSimulationParameter(sim_handle_tree,'particlesAreVisible',tostring(particlesAreVisible))
	simulateParticles=simGetScriptSimulationParameter(sim_handle_self,'simulateParticles')
	simSetScriptSimulationParameter(sim_handle_tree,'simulateParticles',tostring(simulateParticles))

	propellerScripts={-1,-1,-1,-1}
	for i=1,4,1 do
		propellerScripts[i]=simGetScriptHandle('Quadricopter_propeller_respondable'..i)
	end
	heli=simGetObjectAssociatedWithScript(sim_handle_self)

	particlesTargetVelocities={0,0,0,0}

	pParam=20
	iParam=.05
	dParam= .25
	vParam=-4

	cumul=0
	lastE=0
	pAlphaE=0
	pBetaE=0
	psp2=0
	psp1=0

	prevEuler=0
	vertRef = 0
	lastVertRef = 0

	fakeShadow=simGetScriptSimulationParameter(sim_handle_self,'fakeShadow')
	if (fakeShadow) then
		shadowCont=simAddDrawingObject(sim_drawing_discpoints+sim_drawing_cyclic+sim_drawing_25percenttransparency+sim_drawing_50percenttransparency+sim_drawing_itemsizes,0.2,0,-1,1)
	end

	-- Prepare 2 floating views with the camera views:
	-- floorCam=simGetObjectHandle('Quadricopter_floorCamera')
	-- frontCam=simGetObjectHandle('Quadricopter_frontCamera')
	-- floorView=simFloatingViewAdd(0.9,0.9,0.2,0.2,0)
	-- frontView=simFloatingViewAdd(0.7,0.9,0.2,0.2,0)
	-- simAdjustView(floorView,floorCam,64)
	-- simAdjustView(frontView,frontCam,64)
end 

-- Clean-Up ---------------------------------------------------------

if (sim_call_type==sim_childscriptcall_cleanup) then 
	simRemoveDrawingObject(shadowCont)
	simFloatingViewRemove(floorView)
	simFloatingViewRemove(frontView)
end 

-- Actuation --------------------------------------------------------
if (sim_call_type==sim_childscriptcall_actuation) then 
	s=simGetObjectSizeFactor(d)
	
	pos=simGetObjectPosition(d,-1)
	if (fakeShadow) then
		itemData={pos[1],pos[2],0.002,0,0,1,0.2*s}
		simAddDrawingObjectItem(shadowCont,itemData)
	end

	
	-- Vertical control:
	targetPos=simGetObjectPosition(targetObj,-1)
	pos=simGetObjectPosition(d,-1)
	l=simGetVelocity(heli)
	vertRef = targetPos[3]
	vertFbk = pos[3]
	e=(vertRef-vertFbk)
	dInput = vertRef-lastVertRef
	cumul=cumul+e
	pv=pParam*e
	thrust=5.335+(pv)+(iParam*cumul)-(dParam*(dInput))+l[3]*vParam
	lastE=e
	lastVertRef = vertRef
	
	-- Horizontal control: 

	sp=simGetObjectPosition(targetObj,d)
	-- print('xPos',sp[1], 'yPos', sp[2], 'zPos', sp[3])
	m=simGetObjectMatrix(d,-1)
	vx={1,0,0}
	vx=simMultiplyVector(m,vx)
	vy={0,1,0}
	vy=simMultiplyVector(m,vy)
	alphaE=(vy[3]-m[12])
	alphaCorr=0.25*alphaE+2.1*(alphaE-pAlphaE)
	betaE=(vx[3]-m[12])
	betaCorr=-0.25*betaE-2.1*(betaE-pBetaE)
	pAlphaE=alphaE
	pBetaE=betaE
	alphaCorr=alphaCorr+sp[2]*0.005+1*(sp[2]-psp2)
	betaCorr=betaCorr-sp[1]*0.005-1*(sp[1]-psp1)
	psp2=sp[2]
	psp1=sp[1]
	
	-- Rotational control:
	euler=simGetObjectOrientation(d,targetObj)
	rotCorr=euler[3]*0.1+2*(euler[3]-prevEuler)
	prevEuler=euler[3]
	
	-- Decide of the motor velocities:
	particlesTargetVelocities[1]=thrust*(1-alphaCorr+betaCorr+rotCorr)
	particlesTargetVelocities[2]=thrust*(1-alphaCorr-betaCorr-rotCorr)
	particlesTargetVelocities[3]=thrust*(1+alphaCorr-betaCorr+rotCorr)
	particlesTargetVelocities[4]=thrust*(1+alphaCorr+betaCorr-rotCorr)
	
	-- Send the desired motor velocities to the 4 rotors:
	for i=1,4,1 do
		simSetScriptSimulationParameter(propellerScripts[i],'particleVelocity',particlesTargetVelocities[i])
	end
end 
