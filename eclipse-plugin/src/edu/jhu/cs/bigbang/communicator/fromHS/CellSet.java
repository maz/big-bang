package edu.jhu.cs.bigbang.communicator.fromHS;

public class CellSet extends Clause{
	private Origin origin;
	private AbstractCellVar cellVar;
	private AbstractFlowVar flowVar;
	public Origin getOrigin() {
		return origin;
	}
	public void setOrigin(Origin origin) {
		this.origin = origin;
	}
	public AbstractCellVar getCellVar() {
		return cellVar;
	}
	public void setCellVar(AbstractCellVar cellVar) {
		this.cellVar = cellVar;
	}
	public AbstractFlowVar getFlowVar() {
		return flowVar;
	}
	public void setFlowVar(AbstractFlowVar flowVar) {
		this.flowVar = flowVar;
	}
	public CellSet(Origin origin, AbstractCellVar cellVar,
			AbstractFlowVar flowVar) {
		super();
		this.origin = origin;
		this.cellVar = cellVar;
		this.flowVar = flowVar;
	}
	
	public String toString() {
    	return " " + cellVar + " <- " + flowVar;
    }
	
	public boolean equals(CellSet cellSetObj) { 
		if(this.origin.equals(cellSetObj.getOrigin()) &&
		   this.flowVar.equals(cellSetObj.getFlowVar()) &&
		   this.cellVar.equals(cellSetObj.getCellVar())) {
			return true;
		} else {
			return false;
		}
	}
	
}
