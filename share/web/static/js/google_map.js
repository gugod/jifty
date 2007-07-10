// XXX: move me to Plugin/GoogleMap's share when that works

if (GMap2) {
    //document.body.onunload = "GUnload()";

if(!Jifty) Jifty = {};
Jifty.GMap = function() {};
Jifty.GMap.location_editor = function(element, x, y, xid, yid, zoom_level, no_marker) {
    if (!GBrowserIsCompatible())
	return;

    var map = new GMap2(element);
    map.enableScrollWheelZoom();
    map.addControl(new GSmallZoomControl());
    map.addControl(new EditLocationControl());
    map.setCenter(new GLatLng(y, x), zoom_level);
    map._jifty_form_x = xid;
    map._jifty_form_y = yid;
    if (!no_maker) {
	map._jifty_location = new GMarker(new GLatLng(y, x));
	map.addOverlay(map._jifty_location);
    }
    GEvent.addListener(map, "click", function(marker, point) {
	if (!marker && map._jifty_edit_control.editing) {
	    map.removeOverlay(map._jifty_location);
	    map._jifty_location = new GMarker(point)
	    map.addOverlay(map._jifty_location);
	}});
}

function EditLocationControl() {}
EditLocationControl.prototype = new GControl();

EditLocationControl.prototype.initialize = function(map) {
  var container = document.createElement("div");

  var EditDiv = document.createElement("div");
  this.setButtonStyle_(EditDiv);
  container.appendChild(EditDiv);
  EditDiv.appendChild(document.createTextNode("Edit"));

  var SearchDiv = document.createElement("div");
  this.setButtonStyle_(SearchDiv);
  SearchDiv.appendChild(document.createTextNode("Search"));

  var editctl = this;
  GEvent.addDomListener(EditDiv, "click", function() {
    if (editctl.editing) {
        var point = map._jifty_location.getPoint();
	$(map._jifty_form_x).value = point.lng()
	$(map._jifty_form_y).value = point.lat()
	EditDiv.innerHTML = "Edit";
	container.removeChild(container.lastChild);
	editctl.editing = false;
    }
    else {
        container.appendChild(SearchDiv);
	EditDiv.innerHTML = "Done";
	editctl.editing = true;
    }
  });

  GEvent.addDomListener(SearchDiv, "click", function() {
	  var element = document.createElement('form');
	  element._map = map;
	  element.setAttribute('onsubmit','_handle_search(this._map, this.firstChild.value); return false;');
	  var field= document.createElement('input');
	  field.setAttribute('type', 'text');
	  field.style.width = '150px';
	  element.appendChild(field);
	  var submit= document.createElement('input');
	  submit.setAttribute('type', 'submit');
	  element.appendChild(submit);
	  map.openInfoWindow(map.getCenter(), element, { maxWidth: 100 } );
  });

  map.getContainer().appendChild(container);
  map._jifty_edit_control = this;
  this.editing = false;
  return container;
}

function _handle_search(map, address) {
    var geocoder = new GClientGeocoder();
    geocoder.getLocations(address,
			  function (result) {
			      if(result.Placemark) {
				  if (result.Placemark.length == 1) {
				      var point = result.Placemark[0].Point.coordinates;
				      map.removeOverlay(map._jifty_location);
				      map._jifty_location = new GMarker(new GLatLng(point[1], point[0]));
				      map.addOverlay(map._jifty_location);
				      map.closeInfoWindow();
				      map.setCenter(map._jifty_location.getPoint(), 8+result.Placemark[0].AddressDetails.Accuracy);
				  }
				  else {
				      alert('not yet');
				  }
			      }
			      else {
				  alert('address not found');
			      }
			  });
}

EditLocationControl.prototype.getDefaultPosition = function() {
  return new GControlPosition(G_ANCHOR_BOTTOM_RIGHT, new GSize(7, 7));
}

EditLocationControl.prototype.setButtonStyle_ = function(button) {
  button.style.textDecoration = "underline";
  button.style.color = "#0000cc";
  button.style.backgroundColor = "white";
  button.style.font = "small Arial";
  button.style.fontSize = "0.8em";
  button.style.border = "1px solid black";
  button.style.padding = "2px";
  button.style.marginBottom = "3px";
  button.style.textAlign = "center";
  button.style.width = "4em";
  button.style.cursor = "pointer";
}


}
