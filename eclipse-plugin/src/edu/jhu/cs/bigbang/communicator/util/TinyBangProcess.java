package edu.jhu.cs.bigbang.communicator.util;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;

import edu.jhu.cs.bigbang.communicator.exception.*;
import edu.jhu.cs.bigbang.communicator.fromHS.*;
import edu.jhu.cs.bigbang.communicator.toHS.*;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

public class TinyBangProcess {
	
	private Process p;
	private OutputStream stToHaskell = null;
	private InputStream stFromHaskell = null;
	private InputStream stderr = null;			
	
	public TinyBangProcess(ProcessBuilder pb) {
		try {
			p = pb.start();
			stToHaskell = p.getOutputStream();
			stFromHaskell = p.getInputStream();
			stderr = p.getErrorStream();
		} catch (IOException e) {		
			printf("Encount IOException, when tring to get stdin, stdout or stderr from subprocess");
		}
	}
	
	public void sendObj(ToHaskellObject tho) {
		GsonBuilder gb = new GsonBuilder();
		Gson g = gb.registerTypeHierarchyAdapter(ToHaskellObject.class, new ToHaskellObjectAdapter()).create(); 		
		String inputStr = g.toJson(tho);
		printf(tho.getClass().getSimpleName());
		printf("Json String which will be sent to haskell: " + inputStr);
		
		try {			
			stToHaskell.write(inputStr.getBytes());			
			stToHaskell.close();
			
			// if there is error message, print them out
			BufferedReader br_err = new BufferedReader(new InputStreamReader(stderr));			
			String errMsg = null;
			
			while ((errMsg=br_err.readLine()) != null) {
				System.out.println(errMsg);
			}
			
		} catch (IOException e) {		
			printf("Encount IOException, when tring to write json string to interpreter stdin");
		}			
	}
	
	public <T extends CommunicatorSerializable> T readObject(Class<T> clazz) throws TinyBangProtocolException, TinyBangInternalErrorException {
				
		BufferedReader br = new BufferedReader(new InputStreamReader(stFromHaskell));				
		String resultStr = null;
		FromHaskellObject fko = null;				
		
		try {
			// get the right json format for gson 
			resultStr = br.readLine();
			printf("Json string received from haskell: " + resultStr);			
			
			GsonBuilder gb = new GsonBuilder();
	 		gb.registerTypeHierarchyAdapter(FromHaskellObject.class, new FromHaskellObjectAdapter());
	 		Gson g = gb.create();	 		
			fko = g.fromJson(resultStr, FromHaskellObject.class);						
			
		} catch (IOException e2) {
			printf("Encount IOException when trying to read stdout.");
		}		
		
		if (fko instanceof ProtocolError) {
			throw new TinyBangProtocolException("Encount a protocol error.");
		} else if (fko instanceof FromHaskellObject) {			
            // The above isInstance check ensures that the following cast is safe
            @SuppressWarnings("...")
            T ret = (T)fko;
            return ret;
        } else {            
        	throw new TinyBangInternalErrorException("Encount an internal error.");									            
        }
				
	}
	
	public void destroySubProcess() {
		p.destroy();
	}
	
	// util
	
	public void printf(Object obj) {
		System.out.println(obj);
	}
	
	public void print(Object obj) {
		System.out.print(obj);
	}
}