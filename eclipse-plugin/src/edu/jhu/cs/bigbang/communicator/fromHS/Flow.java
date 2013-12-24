package edu.jhu.cs.bigbang.communicator.fromHS;

public class Flow extends EvaluatedClause{
	
	private AbstractFlowVar flowVar;
	private FlowKind flowKind;
	private AbstractFlowVar flowVar2;
	
	public AbstractFlowVar getFlowVar() {
		return flowVar;
	}
	
	public void setFlowVar(AbstractFlowVar flowVar) {
		this.flowVar = flowVar;
	}
	
	public FlowKind getFlowKind() {
		return flowKind;
	}
	
	public void setFlowKind(FlowKind flowKind) {
		this.flowKind = flowKind;
	}
	
	public AbstractFlowVar getFlowVar2() {
		return flowVar2;
	}
	
	public void setFlowVar2(AbstractFlowVar flowVar2) {
		this.flowVar2 = flowVar2;
	}
	
	public Flow(Origin origin, AbstractFlowVar flowVar, FlowKind flowKind,
			AbstractFlowVar flowVar2) {
		super(origin);
		this.flowVar = flowVar;
		this.flowKind = flowKind;
		this.flowVar2 = flowVar2;
	}

}