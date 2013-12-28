package edu.jhu.cs.bigbang.communicator.fromHS;

public class PrimChar extends PrimitiveType{
	private Origin origin;

	public Origin getOrigin() {
		return origin;
	}

	public void setOrigin(Origin origin) {
		this.origin = origin;
	}

	public PrimChar(Origin origin) {
		super();
		this.origin = origin;
	}
	
	public String toString() {
		return  "char";
	}
	
	public boolean equals(PrimChar primCharObj) {
		if(this.origin.equals(primCharObj.getOrigin())) {
			return true;
		} else {
			return false;
		}
	}
	
}
