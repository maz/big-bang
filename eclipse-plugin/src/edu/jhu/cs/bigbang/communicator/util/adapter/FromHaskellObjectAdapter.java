package edu.jhu.cs.bigbang.communicator.util.adapter;

import java.lang.reflect.Type;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonDeserializationContext;
import com.google.gson.JsonDeserializer;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParseException;

import edu.jhu.cs.bigbang.communicator.exception.TinyBangDeserializationInternalFailureException;
import edu.jhu.cs.bigbang.communicator.exception.TinyBangUnrecognizedDeserializationTypeException;
import edu.jhu.cs.bigbang.communicator.fromHS.*;

public class FromHaskellObjectAdapter implements
		JsonDeserializer<FromHaskellObject> {

	@Override
	public FromHaskellObject deserialize(JsonElement je, Type typeOfSrc,
			JsonDeserializationContext context) throws JsonParseException {
		
		JsonObject jo = (JsonObject) je;
		
		String type = jo.get("type").getAsString();

		FromHaskellObject fho = null;
		
		GsonBuilder flowVarGb = new GsonBuilder();
        flowVarGb.registerTypeHierarchyAdapter(AbstractFlowVar.class, new AbstractFlowVarAdapter());
        Gson flowVarG = flowVarGb.create();
		
        GsonBuilder valueGb = new GsonBuilder();
        valueGb.registerTypeHierarchyAdapter(Value.class, new ValueAdapter());
        Gson valueG = valueGb.create();
        
        GsonBuilder cellVarGb = new GsonBuilder();
        cellVarGb.registerTypeHierarchyAdapter(AbstractCellVar.class, new AbstractCellVarAdapter());
        Gson cellVarG = cellVarGb.create();
        			
        GsonBuilder evalErrorGb = new GsonBuilder();
        evalErrorGb.registerTypeHierarchyAdapter(EvalError.class, new EvalErrorAdapter());
        Gson evalErrorG = evalErrorGb.create();
        
        GsonBuilder clauseGb = new GsonBuilder();
        clauseGb.registerTypeHierarchyAdapter(Clause.class, new ClauseAdapter());
        Gson clauseG = clauseGb.create();
        
		if (type.equals("LexerFailure")) {
		    	
			String errMsg = jo.get("errMsg").getAsString();
			fho = new BMLexFailure(1, errMsg);
			
		} else if (type.equals("ParserError")) {
			
			String errMsg = jo.get("errMsg").getAsString();
			fho = new BMParserFailure(1, errMsg);
			
		} else if (type.equals("EvaluationFailure")) {
			
			EvalError evalError = evalErrorG.fromJson(jo.get("evalError").getAsJsonObject(), EvalError.class);
			JsonArray clauseJsonArr = jo.get("clauseLst").getAsJsonArray();
			Iterator<JsonElement> i = clauseJsonArr.iterator();
			ArrayList<Clause> clauseLst = new ArrayList<Clause>();
			
			while (i.hasNext()) {
				Clause clause = clauseG.fromJson(i.next(), Clause.class);
				clauseLst.add(clause);
			}
		
			fho = new BMEvalFailure(1, evalError, clauseLst);
			
		} else if (type.equals("BatchModeResult")) {

			AbstractFlowVar flowVar =  flowVarG.fromJson(jo.get("flowVar").getAsJsonObject(), AbstractFlowVar.class);
			
			HashMap<AbstractFlowVar, Value> flowToValueMap = new HashMap<AbstractFlowVar, Value>();
			HashMap<AbstractCellVar, AbstractFlowVar> cellToFlowMap = new HashMap<AbstractCellVar, AbstractFlowVar>();
						
			// Get flowToValueMap
			JsonArray flowToValueMapArr = jo.get("flowToValueMap").getAsJsonArray();
			
			Iterator<JsonElement> outerI = flowToValueMapArr.iterator();
			while (outerI.hasNext()) {
				
				JsonArray eleOfMap = (JsonArray) outerI.next();
				
				// The format is known in advanced, the key is flowVar and the value is Value object
				JsonElement flowVarJe = eleOfMap.get(0);
				AbstractFlowVar flowVar1 = flowVarG.fromJson(flowVarJe, AbstractFlowVar.class);
				
				JsonElement valueJe = eleOfMap.get(1);
				Value value = valueG.fromJson(valueJe, Value.class);
				
				flowToValueMap.put(flowVar1, value);
			}
			
			// Get cellToFlowMap
			JsonArray cellToFlowMapArr = jo.get("cellToFlowMap").getAsJsonArray();
			
			Iterator<JsonElement> cellToFlowOuterI = cellToFlowMapArr.iterator();
			while (cellToFlowOuterI.hasNext()) {
				
				JsonArray eleOfMap = (JsonArray) cellToFlowOuterI.next();
				
				// The format is known in advanced, the key is the cellVar and the value is flowVar
				JsonElement cellVarJe = eleOfMap.get(0);
				AbstractCellVar cellVar = cellVarG.fromJson(cellVarJe, AbstractCellVar.class);
				
				JsonElement flowVarJe = eleOfMap.get(1);
				AbstractFlowVar flowVar2 = flowVarG.fromJson(flowVarJe, AbstractFlowVar.class);
				
				cellToFlowMap.put(cellVar, flowVar2);
			}
			
			fho = new BatchModeResult(1, flowVar, flowToValueMap, cellToFlowMap);
		} else {
			
			throw new TinyBangDeserializationInternalFailureException(new TinyBangUnrecognizedDeserializationTypeException(type));
			
		}
		
		return fho;
	}
}