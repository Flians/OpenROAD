// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

#include "opendb/db.h"
#include "opendb/lefin.h"
#include "opendb/defin.h"
#include "opendb/defout.h"
#include "Machine.hh"
#include "Report.hh"
#include "VerilogWriter.hh"
#include "db_sta/dbSta.hh"
#include "openroad/OpenRoad.hh"
#include "dbReadVerilog.hh"
#include "db_sta/dbSta.hh"
#include "StaMain.hh"
#include "openroad/InitOpenRoad.hh"
#include "db_sta/MakeDbSta.hh"

namespace sta {
extern const char *openroad_tcl_inits[];
}

// Swig uses C linkage for init functions.
extern "C" {
extern int Openroad_Init(Tcl_Interp *interp);
extern int Opendbtcl_Init(Tcl_Interp *interp);
extern int Replace_Init(Tcl_Interp *interp);
}

namespace ord {

using odb::dbLib;
using sta::Sta;
using sta::dbSta;
using sta::initSta;
using odb::dbDatabase;
using sta::evalTclInit;

OpenRoad *OpenRoad::openroad_ = nullptr;

OpenRoad::OpenRoad()
{
  openroad_ = this;
}

OpenRoad::~OpenRoad()
{
  delete sta_;
  odb::dbDatabase::destroy(db_);
}

sta::dbNetwork *
OpenRoad::getDbNetwork()
{
  return sta_->getDbNetwork();
}

////////////////////////////////////////////////////////////////

void
initOpenRoad(Tcl_Interp *interp,
	     const char *prog_arg)
{
  OpenRoad *openroad = new OpenRoad;
  openroad->init(interp, prog_arg);
}

void
OpenRoad::init(Tcl_Interp *interp,
	       const char *prog_arg)
{
  Openroad_Init(interp);
  // Import TCL scripts.
  evalTclInit(interp, sta::openroad_tcl_inits);

  db_ = dbDatabase::create();
  Opendbtcl_Init(interp);

  sta_ = sta::makeDbSta(db_, interp);

  resizer_ = sta::makeResizer(sta_, interp, prog_arg);

  Replace_Init(interp);
}

////////////////////////////////////////////////////////////////

void
OpenRoad::readLef(const char *filename,
		  const char *lib_name,
		  bool make_tech,
		  bool make_library)
{
  odb::lefin lef_reader(db_, false);
  if (make_tech && make_library) {
    dbLib *lib = lef_reader.createTechAndLib(lib_name, filename);
    if (lib)
      sta_->readLefAfter(lib);
  }
  else if (make_tech)
    lef_reader.createTech(filename);
  else if (make_library) {
    dbLib *lib = lef_reader.createLib(lib_name, filename);
    if (lib)
      sta_->readLefAfter(lib);
  }
}

void
OpenRoad::readDef(const char *filename)
{
  odb::defin def_reader(db_);
  std::vector<odb::dbLib *> search_libs;
  for (odb::dbLib *lib : db_->getLibs())
    search_libs.push_back(lib);
  def_reader.createChip(search_libs, filename);
  sta_->readDefAfter();
}

void
OpenRoad::writeDef(const char *filename)
{
  odb::dbChip *chip = db_->getChip();
  if (chip) {
    odb::dbBlock *block = chip->getBlock();
    if (block) {
      odb::defout def_writer;
      def_writer.writeBlock(block, filename);
    }
  }
}

void
OpenRoad::readDb(const char *filename)
{
  FILE *stream = fopen(filename, "r");
  if (stream) {
    db_->read(stream);
    sta_->readDbAfter();
    fclose(stream);
  }
}

void
OpenRoad::writeDb(const char *filename)
{
  FILE *stream = fopen(filename, "w");
  if (stream) {
    db_->write(stream);
    fclose(stream);
  }
}

void
OpenRoad::readVerilog(const char *filename)
{
  ord::dbReadVerilog(filename, sta_->networkReader());
}

void
OpenRoad::linkDesign(const char *design_name)

{
  dbLinkDesign(design_name, db_);
  sta_->readDbAfter();
}

void
OpenRoad::writeVerilog(const char *filename,
		       bool sort)
{
  sta::writeVerilog(filename, sort, sta_->network());
}

} // namespace
