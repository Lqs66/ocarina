------------------------------------------------------------------------------
--                                                                          --
--                           OCARINA COMPONENTS                             --
--                                                                          --
--  O C A R I N A . B A C K E N D S . P O _ H I _ C . D E P L O Y M E N T   --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--          Copyright (C) 2008-2011, European Space Agency (ESA).           --
--                                                                          --
-- Ocarina  is free software;  you  can  redistribute  it and/or  modify    --
-- it under terms of the GNU General Public License as published by the     --
-- Free Software Foundation; either version 2, or (at your option) any      --
-- later version. Ocarina is distributed  in  the  hope  that it will be    --
-- useful, but WITHOUT ANY WARRANTY;  without even the implied warranty of  --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General --
-- Public License for more details. You should have received  a copy of the --
-- GNU General Public License distributed with Ocarina; see file COPYING.   --
-- If not, write to the Free Software Foundation, 51 Franklin Street, Fifth --
-- Floor, Boston, MA 02111-1301, USA.                                       --
--                                                                          --
-- As a special exception,  if other files  instantiate  generics from this --
-- unit, or you link  this unit with other files  to produce an executable, --
-- this  unit  does not  by itself cause  the resulting  executable to be   --
-- covered  by the  GNU  General  Public  License. This exception does not  --
-- however invalidate  any other reasons why the executable file might be   --
-- covered by the GNU Public License.                                       --
--                                                                          --
--                 Ocarina is maintained by the Ocarina team                --
--                       (ocarina-users@listes.enst.fr)                     --
--                                                                          --
------------------------------------------------------------------------------

with Namet;
with Utils; use Utils;
with Ocarina.ME_AADL;
with Ocarina.ME_AADL.AADL_Instances.Nodes;
with Ocarina.ME_AADL.AADL_Instances.Nutils;
with Ocarina.ME_AADL.AADL_Instances.Entities;

with Ocarina.Backends.Utils;
with Ocarina.Backends.C_Values;
with Ocarina.Backends.C_Tree.Nutils;
with Ocarina.Backends.C_Tree.Nodes;
with Ocarina.Backends.C_Common.Mapping;
with Ocarina.Backends.PO_HI_C.Runtime;
with Ocarina.Backends.Properties;
with Ocarina.Backends.Messages;

with Ocarina.Instances.Queries;

package body Ocarina.Backends.PO_HI_C.Deployment is

   use Namet;
   use Ocarina.ME_AADL;
   use Ocarina.ME_AADL.AADL_Instances.Nodes;
   use Ocarina.ME_AADL.AADL_Instances.Entities;
   use Ocarina.Backends.Utils;
   use Ocarina.Backends.C_Values;
   use Ocarina.Backends.C_Tree.Nutils;
   use Ocarina.Backends.C_Common.Mapping;
   use Ocarina.Backends.PO_HI_C.Runtime;
   use Ocarina.Backends.Properties;
   use Ocarina.Backends.Messages;
   use Ocarina.Instances.Queries;

   package AAN renames Ocarina.ME_AADL.AADL_Instances.Nodes;
   package AAU renames Ocarina.ME_AADL.AADL_Instances.Nutils;
   package CV renames Ocarina.Backends.C_Values;
   package CTN renames Ocarina.Backends.C_Tree.Nodes;
   package CTU renames Ocarina.Backends.C_Tree.Nutils;

   Entity_Array      : Node_Id;
   Devices_Array     : Node_Id;
   Port_To_Devices   : Node_Id;

   function Is_Added (P : Node_Id; E : Node_Id) return Boolean;
   function Added_Internal_Name (P : Node_Id; E : Node_Id) return Name_Id;

   --------------
   -- Is_Added --
   --------------

   function Is_Added (P : Node_Id; E : Node_Id) return Boolean is
      I_Name : constant Name_Id := Added_Internal_Name (P, E);
   begin
      return Get_Name_Table_Byte (I_Name) = 1;
   end Is_Added;

   -------------------------
   -- Added_Internal_Name --
   -------------------------

   function Added_Internal_Name (P : Node_Id; E : Node_Id) return Name_Id is
   begin
      Set_Str_To_Name_Buffer ("%add%enumerator%");
      Add_Nat_To_Name_Buffer (Nat (P));
      Add_Char_To_Name_Buffer ('%');
      Add_Nat_To_Name_Buffer (Nat (E));

      return Name_Find;
   end Added_Internal_Name;

   -----------------
   -- Header_File --
   -----------------

   package body Header_File is

      procedure Visit_Architecture_Instance (E : Node_Id);
      procedure Visit_Component_Instance (E : Node_Id);
      procedure Visit_System_Instance (E : Node_Id);
      procedure Visit_Process_Instance (E : Node_Id);
      procedure Visit_Thread_Instance (E : Node_Id);
      procedure Visit_Subprogram_Instance (E : Node_Id);
      procedure Visit_Device_Instance (E : Node_Id);
      procedure Visit_Bus_Instance (E : Node_Id);

      procedure Set_Added (P : Node_Id; E : Node_Id);

      procedure Append_Existing
        (S : Node_Id;
         L : List_Id;
         Id : in out Unsigned_Long_Long;
         Is_Entity : Boolean := False);

      --  Append a node in a List. If the node was node already processed,
      --  it assigns a value (using the Id) argument to the node and bind
      --  it to the Backend Node of S. Is a value was already assigned, it
      --  simply uses it and append the it in the list.
      --  This function is used to warrant that all entities will have
      --  the same values on each node.

      Node_Enumerator_List          : List_Id;
      Tasks_Enumerator_List         : List_Id;
      Devices_Enumerator_List       : List_Id;
      Buses_Enumerator_List         : List_Id;
      Entity_Enumerator_List        : List_Id;
      Global_Port_List              : List_Id;
      Global_Port_Names             : Node_Id;
      Global_Port_Model_Names       : Node_Id;
      Local_Port_List               : List_Id;

      Nb_Nodes                      : Unsigned_Long_Long;

      Current_Process_Instance      : Node_Id := No_Node;

      Global_Port_To_Entity     : Node_Id;
      Global_Port_To_Local      : Node_Id;
      Local_Port_Values         : Node_Id;

      Invalid_Local_Port_Added  : Boolean := False;
      Invalid_Global_Port_Added : Boolean := False;
      Invalid_Entity_Added      : Boolean := False;

      Current_Device : Node_Id := No_Node;
      --  Current_Process : Node_Id := No_Node;

      --  Point to the process currently visited. When we visit a process
      --  we look at all its ports and visit the called subprograms. So,
      --  we need to know if these subprograms are linked with the currrent
      --  process.

      Node_Identifier          : Unsigned_Long_Long := 0;
      Global_Port_Identifier   : Unsigned_Long_Long := 0;
      Local_Port_Identifier    : Unsigned_Long_Long := 0;
      Entity_Identifier        : Unsigned_Long_Long := 0;
      Task_Identifier          : Unsigned_Long_Long := 0;
      Nb_Protected             : Unsigned_Long_Long := 0;
      Device_Id                : Unsigned_Long_Long := 0;
      Bus_Id                   : Unsigned_Long_Long := 0;
      Nb_Ports_In_Process      : Unsigned_Long_Long := 0;
      Nb_Ports_Total           : Unsigned_Long_Long := 0;
      Total_Ports_Node         : Node_Id := No_Node;
      Nb_Entities_Node         : Node_Id := No_Node;
      Nb_Devices_Node          : Node_Id := No_Node;
      Nb_Buses_Node            : Node_Id := No_Node;

      --  The information from Simulink can come
      --  from both data and subprograms. So, to avoid
      --  conflict, we add relevant informations from
      --  the first component that have them. And for other
      --  components, we add nothing.

      ---------------------
      -- Append_Existing --
      ---------------------

      procedure Append_Existing
        (S         : Node_Id;
         L         : List_Id;
         Id        : in out Unsigned_Long_Long;
         Is_Entity : Boolean := False) is
         N         : Node_Id;
      begin
         if No (Backend_Node (Identifier (S))) or else
            (Present (Backend_Node (Identifier (S))) and then
            No (CTN.Enumerator_Node
                 (Backend_Node (Identifier (S))))) then

            N := Make_Expression
               (Make_Defining_Identifier
                  (Map_C_Enumerator_Name
                     (S,
                     Custom_Parent => Current_Device,
                     Entity => Is_Entity)),
               Op_Equal,
               Make_Literal
                  (CV.New_Int_Value (Id, 0, 10)));
            Bind_AADL_To_Enumerator (Identifier (S), N);
            Append_Node_To_List (N, L);
            Id := Id + 1;
         end if;
      end Append_Existing;

      ---------------
      -- Set_Added --
      ---------------

      procedure Set_Added (P : Node_Id; E : Node_Id) is
         I_Name : constant Name_Id := Added_Internal_Name (P, E);
      begin
         Set_Name_Table_Byte (I_Name, 1);
      end Set_Added;

      -----------
      -- Visit --
      -----------

      procedure Visit (E : Node_Id) is
      begin
         case Kind (E) is
            when K_Architecture_Instance =>
               Visit_Architecture_Instance (E);

            when K_Component_Instance =>
               Visit_Component_Instance (E);

            when others =>
               null;
         end case;
      end Visit;

      ---------------------------------
      -- Visit_Architecture_Instance --
      ---------------------------------

      procedure Visit_Architecture_Instance (E : Node_Id) is
      begin
         Visit (Root_System (E));
      end Visit_Architecture_Instance;

      ------------------------------
      -- Visit_Component_Instance --
      ------------------------------

      procedure Visit_Component_Instance (E : Node_Id) is
         Category : constant Component_Category
           := Get_Category_Of_Component (E);
      begin
         case Category is
            when CC_System =>
               Visit_System_Instance (E);

            when CC_Process =>
               Visit_Process_Instance (E);

            when CC_Thread =>
               Visit_Thread_Instance (E);

            when CC_Subprogram =>
               Visit_Subprogram_Instance (E);

            when CC_Device =>
               Visit_Device_Instance (E);

            when CC_Bus =>
               Visit_Bus_Instance (E);

            when others =>
               null;
         end case;
      end Visit_Component_Instance;

      ------------------------
      -- Visit_Bus_Instance --
      ------------------------

      procedure Visit_Bus_Instance (E : Node_Id) is
         N        : Node_Id;
      begin
         N := Make_Expression
           (Make_Defining_Identifier
            (Map_C_Enumerator_Name
             (E, Entity => False)),
            Op_Equal,
            (Make_Literal
          (CV.New_Int_Value (Bus_Id, 0, 10))));
         Append_Node_To_List
           (N, Buses_Enumerator_List);

         Bus_Id  := Bus_Id + 1;

         CTN.Set_Value
            (Nb_Buses_Node, New_Int_Value
             (Bus_Id, 1, 10));

      end Visit_Bus_Instance;

      ---------------------------
      -- Visit_Device_Instance --
      ---------------------------

      procedure Visit_Device_Instance (E : Node_Id) is
         N        : Node_Id;
         Conf_Str : Name_Id := No_Name;
         Tmp_Name : Name_Id;
      begin
         Current_Device := E;

         if Current_Process_Instance /= No_Node and then
            Get_Bound_Processor (E) =
            Get_Bound_Processor (Current_Process_Instance) then

            if Backend_Node (Identifier (E)) /= No_Node and then
               CTN.Enumerator_Node
                  (Backend_Node (Identifier (E))) /= No_Node then
               return;
            end if;

            Bind_AADL_To_Enumerator
               (Identifier (E),
                Make_Defining_Identifier
                  (Map_C_Enumerator_Name (E, Entity => False)));

            N := Make_Expression
              (Make_Defining_Identifier
               (Map_C_Enumerator_Name
                (E, Entity => False)),
               Op_Equal,
               (Make_Literal
             (CV.New_Int_Value (Device_Id, 0, 10))));
            Append_Node_To_List
              (N, Devices_Enumerator_List);

            Device_Id  := Device_Id + 1;

            CTN.Set_Value
               (Nb_Devices_Node, New_Int_Value
                (Device_Id, 1, 10));

            if Get_Location (E) /= No_Name then
               Get_Name_String (Get_Location (E));
               Conf_Str := Name_Find;
               if Get_Port_Number (E) /= Properties.No_Value then
                  Set_Str_To_Name_Buffer (":");
                  Add_Str_To_Name_Buffer
                     (Value_Id'Image (Get_Port_Number (E)));
                  Tmp_Name := Name_Find;
               end if;
               Get_Name_String (Conf_Str);
               Get_Name_String_And_Append (Tmp_Name);
               Conf_Str := Name_Find;
            elsif Is_Defined_Property (E, "deployment::channel_address") then
               Set_Str_To_Name_Buffer
                  (Unsigned_Long_Long'Image
                     (Get_Integer_Property
                        (E, "deployment::channel_address")));
               Conf_Str := Name_Find;
               if Is_Defined_Property (E, "deployment::process_id") then
                  Set_Str_To_Name_Buffer
                  (Unsigned_Long_Long'Image
                   (Get_Integer_Property (E, "deployment::process_id")));
                  Tmp_Name := Name_Find;
                  Get_Name_String (Conf_Str);
                  Add_Str_To_Name_Buffer (":");
                  Get_Name_String_And_Append (Tmp_Name);
                  Conf_Str := Name_Find;
               end if;
            elsif Is_Defined_Property (E, "deployment::configuration") and then
               Get_String_Property
                  (E, "deployment::configuration") /= No_Name then
               Get_Name_String
                  (Get_String_Property
                     (E, "deployment::configuration"));
               Conf_Str := Name_Find;
            end if;

            if Conf_Str /= No_Name then
               Append_Node_To_List
               (Make_Literal
                (CV.New_Pointed_Char_Value (Conf_Str)),
               CTN.Values (Devices_Array));
            else
               Append_Node_To_List
               (Make_Literal
                (CV.New_Pointed_Char_Value
                 (Get_String_Name ("noaddr"))),
               CTN.Values (Devices_Array));
            end if;

         end if;

         Current_Device := No_Node;
      end Visit_Device_Instance;

      ----------------------------
      -- Visit_Process_Instance --
      ----------------------------

      procedure Visit_Process_Instance (E : Node_Id) is
         U           : constant Node_Id
               := CTN.Distributed_Application_Unit
                  (CTN.Naming_Node (Backend_Node (Identifier (E))));
         P           : constant Node_Id := CTN.Entity (U);
         S           : constant Node_Id := Parent_Subcomponent (E);
         Root_Sys    : constant Node_Id
           := Parent_Component (Parent_Subcomponent (E));
         Driver_Name : Name_Id;
         Q           : Node_Id;
         N           : Node_Id;
         C           : Node_Id;
         F           : Node_Id;
         Data        : Node_Id;
         Src         : Node_Id;
         Dst         : Node_Id;
         Parent      : Node_Id;
         The_System  : constant Node_Id := Parent_Component
           (Parent_Subcomponent (E));
         Device_Implementation : Node_Id;
      begin
         pragma Assert (AAU.Is_System (Root_Sys));

         Nb_Nodes := 0;

         Set_Added (E, E);

         Current_Process_Instance := E;

         Tasks_Enumerator_List      := New_List (CTN.K_Enumeration_Literals);
         Node_Enumerator_List       := New_List (CTN.K_Enumeration_Literals);

         Push_Entity (P);
         Push_Entity (U);
         Set_Deployment_Header;

         Node_Identifier       := 0;
         Task_Identifier       := 0;
         Nb_Protected          := 0;
         Nb_Ports_In_Process   := 0;

         N := Make_Define_Statement
         (Defining_Identifier =>
          (RE (RE_My_Node)),
          Value => Make_Defining_Identifier
          (Map_C_Enumerator_Name (Parent_Subcomponent (E))));
         Append_Node_To_List
         (N, CTN.Declarations (Current_File));

         --  Visit all devices attached to the parent system that
         --  share the same processor as process E.

         if not AAU.Is_Empty (Subcomponents (The_System)) then
            C := First_Node (Subcomponents (The_System));
            while Present (C) loop
               if AAU.Is_Device (Corresponding_Instance (C))
               and then
                 Get_Bound_Processor (Corresponding_Instance (C))
                 = Get_Bound_Processor (E)
               then
                  --  Build the enumerator corresponding to the device
                  --  Note: we reuse the process name XXX

                  Visit_Device_Instance (Corresponding_Instance (C));

                  Current_Device := Corresponding_Instance (C);

                  Device_Implementation :=
                     Get_Implementation (Corresponding_Instance (C));

                  if Device_Implementation /= No_Node then
                     if not AAU.Is_Empty
                        (AAN.Subcomponents (Device_Implementation)) then
                        N := First_Node (Subcomponents
                           (Device_Implementation));
                        while Present (N) loop
                           Visit_Component_Instance
                              (Corresponding_Instance (N));
                           N := Next_Node (N);
                        end loop;
                     end if;
                  end if;

                  Current_Device := No_Node;

               end if;
               C := Next_Node (C);
            end loop;
         end if;

         --  Visit all the subcomponents of the process

         if not AAU.Is_Empty (Subcomponents (E)) then
            C := First_Node (Subcomponents (E));

            while Present (C) loop
               if AAU.Is_Data (Corresponding_Instance (C)) then
                  N := Make_Literal
                    (New_Int_Value
                     (Nb_Protected, 1, 10));
                  Bind_AADL_To_Default_Value
                 (Identifier (C), N);

                  Nb_Protected := Nb_Protected + 1;
               else
                  --  Visit the component instance corresponding to the
                  --  subcomponent S.
                  Visit (Corresponding_Instance (C));
               end if;

               C := Next_Node (C);
            end loop;
         end if;

         --  For each of the processes P connected to E, (1) we add an
         --  enumerator corresponding to P and (2) for each one of the
         --  threads of P, we add an enumerator.

         if not AAU.Is_Empty (Features (E)) then
            F := First_Node (Features (E));

            while Present (F) loop
               --  The sources of F

               if not AAU.Is_Empty (Sources (F)) then
                  Src := First_Node (Sources (F));

                  while Present (Src) loop

                     Parent := Parent_Component (Item (Src));

                     if AAU.Is_Process (Parent)
                       and then Parent /= E
                     then
                        Set_Added (Parent, E);
                        --  Traverse all the subcomponents of Parent

                        if not AAU.Is_Empty (Subcomponents (Parent)) then
                           C := First_Node (Subcomponents (Parent));

                           while Present (C) loop
                              Visit (Corresponding_Instance (C));

                              C := Next_Node (C);
                           end loop;
                        end if;

                        --  Mark P as being Added
                     elsif AAU.Is_Device (Parent)
                        and then Parent /= E then
                        Driver_Name := Get_Driver_Name (Parent);

                        if Driver_Name /= No_Name then
                           Set_Str_To_Name_Buffer ("__PO_HI_NEED_DRIVER_");
                           Get_Name_String_And_Append (Driver_Name);

                           Driver_Name := Name_Find;
                           Driver_Name := To_Upper (Driver_Name);

                           Add_Define_Deployment
                                    (Make_Defining_Identifier
                                       (Driver_Name,
                                       C_Conversion => False));
                        end if;
                     end if;

                     Src := Next_Node (Src);
                  end loop;
               end if;

               --  The destinations of F

               if not AAU.Is_Empty (Destinations (F)) then
                  Dst := First_Node (Destinations (F));

                  while Present (Dst) loop
                     Parent := Parent_Component (Item (Dst));

                     if AAU.Is_Process (Parent)
                       and then Parent /= E
                     then
                        Set_Added (Parent, E);

                        if not AAU.Is_Empty (Subcomponents (Parent)) then
                           C := First_Node (Subcomponents (Parent));

                           while Present (C) loop
                              Visit (Corresponding_Instance (C));

                              C := Next_Node (C);
                           end loop;
                        end if;
                     elsif AAU.Is_Device (Parent)
                        and then Parent /= E then
                        Driver_Name := Get_Driver_Name (Parent);

                        if Driver_Name /= No_Name then
                           Set_Str_To_Name_Buffer ("__PO_HI_NEED_DRIVER_");
                           Get_Name_String_And_Append (Driver_Name);

                           Driver_Name := Name_Find;
                           Driver_Name := To_Upper (Driver_Name);

                           Append_Node_To_List
                              (Make_Define_Statement
                                 (Defining_Identifier =>
                                    (Make_Defining_Identifier
                                       (Driver_Name,
                                       C_Conversion => False)),
                                 Value =>
                                    (Make_Literal
                                       (CV.New_Int_Value (1, 1, 10)))),
                              CTN.Declarations (Current_File));
                        end if;
                     end if;

                     Dst := Next_Node (Dst);
                  end loop;
               end if;

               if Is_Data (F) then
                  if Get_Source_Language (Corresponding_Instance (F))
                     = Language_Simulink then
                     Data := Corresponding_Instance (F);

                     if Get_Source_Name (Data) /= No_Name then
                        N := Make_Define_Statement
                           (Defining_Identifier =>
                              (RE (RE_Simulink_Node)),
                           Value => Make_Defining_Identifier
                                    (Get_Source_Name (Data)));
                        Append_Node_To_List
                           (N, CTN.Declarations (Current_File));

                        N := Make_Define_Statement
                           (Defining_Identifier =>
                              (RE (RE_Simulink_Init_Func)),
                           Value => Map_Simulink_Init_Func (Data));
                        Append_Node_To_List
                           (N, CTN.Declarations (Current_File));

                        N := Make_Define_Statement
                           (Defining_Identifier =>
                              (RE (RE_Simulink_Model_Type)),
                           Value => Map_Simulink_Model_Type (Data));
                        Append_Node_To_List
                           (N, CTN.Declarations (Current_File));
                     end if;
                  end if;

               end if;

               F := Next_Node (F);
            end loop;
         end if;

         Q := First_Node (Subcomponents (Root_Sys));

         while Present (Q) loop
            if AAU.Is_Process (Corresponding_Instance (Q)) then
               if Is_Added (Corresponding_Instance (Q), E) then
                  N := Make_Expression
                     (Make_Defining_Identifier
                        (Map_C_Enumerator_Name (Q)),
                     Op_Equal,
                     Make_Literal
                        (CV.New_Int_Value
                           (Node_Identifier, 0, 10)));
                  Append_Node_To_List
                     (N, Node_Enumerator_List);
                  Node_Identifier := Node_Identifier + 1;
                  Nb_Nodes := Nb_Nodes + 1;
               else
                  N := Make_Expression
                     (Make_Defining_Identifier
                        (Map_C_Enumerator_Name (Q)),
                     Op_Equal,
                     RE (RE_Unused_Node));
                  Append_Node_To_List
                     (N, Node_Enumerator_List);
               end if;
            end if;

            Q := Next_Node (Q);
         end loop;

         --  Create the node enumeration type declaration. Note that
         --  the type creation is possible even the enumeration list
         --  is incomplete. We can do this in the first traversal
         --  since we are sure that the enumerator list is not empty.

         N := Message_Comment ("For each node in the distributed"
                               & " application add an enumerator");
         Append_Node_To_List (N, CTN.Declarations (Current_File));

         N := Make_Full_Type_Declaration
           (Defining_Identifier => RE (RE_Node_T),
            Type_Definition     => Make_Enum_Aggregate
              (Node_Enumerator_List));
         Append_Node_To_List (N, CTN.Declarations (Current_File));

         --  Create the thread enumeration type declaration. Note that
         --  the type creation is possible even the enumeration list
         --  is incomplete. This type may not be generated in case the
         --  application is local.

         if not Is_Empty (Entity_Enumerator_List) then
            N := Message_Comment ("For each thread in the distributed"
                                  & " application nodes, add an"
                                  & " enumerator");
            Append_Node_To_List (N, CTN.Declarations (Current_File));

            if not Invalid_Entity_Added then
               Set_Str_To_Name_Buffer ("invalid_entity");
               N := Make_Expression
                 (Make_Defining_Identifier
                  (Name_Find),
                  Op_Equal,
                  (Make_Literal
                (CV.New_Int_Value (1, -1, 10))));
               Append_Node_To_List
                  (N, Entity_Enumerator_List);
               Invalid_Entity_Added := True;
            end if;

            N := Make_Full_Type_Declaration
              (Defining_Identifier => RE (RE_Entity_T),
               Type_Definition     => Make_Enum_Aggregate
                 (Entity_Enumerator_List));
            Append_Node_To_List (N, CTN.Declarations (Current_File));
         end if;

         Set_Str_To_Name_Buffer ("invalid_task_id");
         N := Make_Expression
           (Make_Defining_Identifier
            (Name_Find),
            Op_Equal,
            (Make_Literal
          (CV.New_Int_Value (1, -1, 10))));
         Append_Node_To_List
            (N, Tasks_Enumerator_List);

         N := Make_Full_Type_Declaration
           (Defining_Identifier => RE (RE_Task_Id),
            Type_Definition     => Make_Enum_Aggregate
              (Tasks_Enumerator_List));
         Append_Node_To_List (N, CTN.Declarations (Current_File));

         N := Make_Full_Type_Declaration
           (Defining_Identifier => RE (RE_Device_Id),
            Type_Definition     => Make_Enum_Aggregate
              (Devices_Enumerator_List));
         Append_Node_To_List (N, CTN.Declarations (Current_File));

         N := Make_Full_Type_Declaration
           (Defining_Identifier => RE (RE_Bus_Id),
            Type_Definition     => Make_Enum_Aggregate
              (Buses_Enumerator_List));
         Append_Node_To_List (N, CTN.Declarations (Current_File));

         N := Make_Define_Statement
           (Defining_Identifier => RE (RE_Nb_Tasks),
             Value => Make_Literal (New_Int_Value (Task_Identifier, 1, 10)));
         Append_Node_To_List (N, CTN.Declarations (Current_File));

         --  Add an enumerator corresponding to an INVALID server
         --  entity to the entity list.

         N := Make_Define_Statement
           (Defining_Identifier => RE (RE_Nb_Protected),
            Value => Make_Literal
              (New_Int_Value
               (Nb_Protected, 1, 10)));
         Append_Node_To_List (N, CTN.Declarations (Current_File));

         N := Make_Define_Statement
           (Defining_Identifier => RE (RE_Nb_Nodes),
            Value => Make_Literal (New_Int_Value (Nb_Nodes, 1, 10)));
         Append_Node_To_List
           (N, CTN.Declarations (Current_File));

         N := Make_Define_Statement
           (Defining_Identifier => RE (RE_Nb_Entities),
            Value => Nb_Entities_Node);
         Append_Node_To_List (N, CTN.Declarations (Current_File));

         N := Make_Define_Statement
           (Defining_Identifier => RE (RE_Nb_Ports),
            Value => Total_Ports_Node);
         Append_Node_To_List (N, CTN.Declarations (Current_File));

         if not Is_Empty (Global_Port_List) then
            if not Invalid_Global_Port_Added then
               Set_Str_To_Name_Buffer ("invalid_port_t");
               N := Make_Expression
                 (Make_Defining_Identifier
                  (Name_Find),
                  Op_Equal,
                  (Make_Literal
                (CV.New_Int_Value (1, -1, 10))));
               Append_Node_To_List
                  (N, Global_Port_List);

               Invalid_Global_Port_Added := True;
            end if;

            N := Make_Full_Type_Declaration
              (Defining_Identifier => RE (RE_Port_T),
               Type_Definition     => Make_Enum_Aggregate
                 (Global_Port_List));
            Append_Node_To_List (N, CTN.Declarations (Current_File));
         end if;

         if not Is_Empty (CTN.Values (Global_Port_To_Local)) then
            Bind_AADL_To_Local_Port (Identifier (S), Global_Port_To_Local);
         end if;

         if not Is_Empty (CTN.Values (Global_Port_To_Entity)) then
            Bind_AADL_To_Global_Port (Identifier (S), Global_Port_To_Entity);
         end if;

         if not Is_Empty (CTN.Values (Global_Port_Names)) then
            Bind_AADL_To_Global_Names (Identifier (S), Global_Port_Names);
         end if;

         if not Is_Empty (CTN.Values (Global_Port_Model_Names)) then
            Bind_AADL_To_Global_Model_Names
               (Identifier (S), Global_Port_Model_Names);
         end if;

         if not Is_Empty (Local_Port_List) then
            if not Invalid_Local_Port_Added then
               Set_Str_To_Name_Buffer ("invalid_local_port_t");
               N := Make_Expression
                 (Make_Defining_Identifier
                  (Name_Find),
                  Op_Equal,
                  (Make_Literal
                (CV.New_Int_Value (1, -1, 10))));
               Append_Node_To_List
                  (N, Local_Port_List);

               Invalid_Local_Port_Added := True;
            end if;

            N := Make_Full_Type_Declaration
               (Defining_Identifier =>
                  RE (RE_Local_Port_T),
               Type_Definition     => Make_Enum_Aggregate
                  (Local_Port_List));
            Append_Node_To_List (N, CTN.Declarations (Current_File));
         end if;

         N := Make_Define_Statement
           (Defining_Identifier => RE (RE_Nb_Devices),
            Value => Nb_Devices_Node);
         Append_Node_To_List
           (N, CTN.Declarations (Current_File));

         N := Make_Define_Statement
           (Defining_Identifier => RE (RE_Nb_Buses),
            Value => Nb_Buses_Node);
         Append_Node_To_List
           (N, CTN.Declarations (Current_File));

         Current_Process_Instance := No_Node;

         Pop_Entity; -- U
         Pop_Entity; -- P
      end Visit_Process_Instance;

      ---------------------------
      -- Visit_System_Instance --
      ---------------------------

      procedure Visit_System_Instance (E : Node_Id) is
         S : Node_Id;
         N : Node_Id;
      begin
         Push_Entity (C_Root);

         Devices_Array              := Make_Array_Values;
         Port_To_Devices            := Make_Array_Values;

         Devices_Enumerator_List    := New_List (CTN.K_Enumeration_Literals);
         Buses_Enumerator_List      := New_List (CTN.K_Enumeration_Literals);
         Global_Port_List           := New_List (CTN.K_Enumeration_Literals);
         Global_Port_Names          := Make_Array_Values;
         Global_Port_Model_Names    := Make_Array_Values;
         Global_Port_To_Entity      := Make_Array_Values;
         Global_Port_To_Local       := Make_Array_Values;
         Entity_Enumerator_List     := New_List (CTN.K_Enumeration_Literals);
         Local_Port_Values          := Make_Array_Values;
         Local_Port_List            := New_List (CTN.K_Enumeration_Literals);
         Total_Ports_Node           := Make_Literal
                                       (New_Int_Value (0, 1, 10));
         Nb_Entities_Node           := Make_Literal
                                       (New_Int_Value (0, 1, 10));
         Nb_Devices_Node            := Make_Literal
                                       (New_Int_Value (0, 1, 10));
         Nb_Buses_Node              := Make_Literal
                                       (New_Int_Value (0, 1, 10));
         Entity_Array               := Make_Array_Values;
         Device_Id                  := 0;

         --  Automatically define invalid identifier
         --  for devices and buses. These are fixed identifier
         --  so that developpers can ALWAYS rely on it.

         Set_Str_To_Name_Buffer ("invalid_device_id");
         N := Make_Expression
           (Make_Defining_Identifier
            (Name_Find),
            Op_Equal,
            (Make_Literal
          (CV.New_Int_Value (1, -1, 10))));
         Append_Node_To_List
            (N, Devices_Enumerator_List);

         Set_Str_To_Name_Buffer ("invalid_bus_id");
         N := Make_Expression
           (Make_Defining_Identifier
            (Name_Find),
            Op_Equal,
            (Make_Literal
          (CV.New_Int_Value (1, -1, 10))));
         Append_Node_To_List
            (N, Buses_Enumerator_List);

         --  Visit all the subcomponents of the system

         if not AAU.Is_Empty (Subcomponents (E)) then
            S := First_Node (Subcomponents (E));
            while Present (S) loop
               --  Visit the component instance corresponding to the
               --  subcomponent S.

               if Get_Current_Backend_Kind = PolyORB_HI_C and then
                  not AAU.Is_Device (Corresponding_Instance (S)) then
                  Visit (Corresponding_Instance (S));
               else
                  Visit (Corresponding_Instance (S));
               end if;
               S := Next_Node (S);
            end loop;
         end if;

         Set_Str_To_Name_Buffer ("constant_out_identifier");
         N := Make_Expression
           (Make_Defining_Identifier
            (Name_Find),
            Op_Equal,
            (Make_Literal
          (CV.New_Int_Value (Global_Port_Identifier + 1, 1, 10))));
         Append_Node_To_List
            (N, Global_Port_List);

         CTN.Set_Value (Total_Ports_Node, New_Int_Value
                                    (Nb_Ports_Total, 1, 10));

         CTN.Set_Value (Nb_Entities_Node, New_Int_Value
                                    (Entity_Identifier, 1, 10));

         Pop_Entity; --  C_Root
      end Visit_System_Instance;

      ---------------------------
      -- Visit_Thread_Instance --
      ---------------------------

      procedure Visit_Thread_Instance (E : Node_Id) is
         N                 : Node_Id;
         F                 : Node_Id;
         P                 : Node_Id;
         S                 : constant Node_Id := Parent_Subcomponent (E);
         Call_Seq          : Node_Id;
         Spg_Call          : Node_Id;
         Used_Bus          : Node_Id;
         Used_Device       : Node_Id;
      begin

         Local_Port_Identifier := 0;
         --  Build the enumerator corresponding to the thread. The
         --  enumerator name is mapped from the the thread name and
         --  its containing process name.

         Append_Existing
           (S, Entity_Enumerator_List, Entity_Identifier, Is_Entity => True);

         if not (Present (Backend_Node (Identifier (S)))) or else
            (Present (Backend_Node (Identifier (S))) and then
             No (CTN.Naming_Node (Backend_Node (Identifier (S)))))
         then
            if Current_Device /= No_Node then
               N := Make_Defining_Identifier
                  (Map_C_Enumerator_Name
                     (Parent_Subcomponent (Current_Process_Instance)));
            else
               N := Make_Defining_Identifier
                  (Map_C_Enumerator_Name (Parent_Subcomponent
                        (Parent_Component (Parent_Subcomponent (E)))));
            end if;
            Bind_AADL_To_Naming (Identifier (S), N);
            Append_Node_To_List (N, CTN.Values (Entity_Array));
         end if;

         if Parent_Component (Parent_Subcomponent (E))
           = Current_Process_Instance then
            N := Make_Expression
              (Make_Defining_Identifier
               (Map_C_Enumerator_Name
                (S, Entity => False)),
               Op_Equal,
               (Make_Literal
             (CV.New_Int_Value (Task_Identifier, 0, 10))));
            Append_Node_To_List
              (N, Tasks_Enumerator_List);
            Task_Identifier := Task_Identifier + 1;
         end if;

         if Current_Device /= No_Node and then
            Current_Process_Instance /= No_Node and then
            Get_Bound_Processor (Current_Device) =
            Get_Bound_Processor (Current_Process_Instance) then
            N := Make_Expression
              (Make_Defining_Identifier
               (Map_C_Enumerator_Name
                (S, Custom_Parent => Current_Device, Entity => False)),
               Op_Equal,
               (Make_Literal
             (CV.New_Int_Value (Task_Identifier, 0, 10))));
            Append_Node_To_List
              (N, Tasks_Enumerator_List);
            Task_Identifier := Task_Identifier + 1;
         end if;

         --  Get the Process parent of the thread

         if Current_Device /= No_Node then
            P := Current_Device;
         else
            P := Parent_Component (S);
         end if;

         N := Make_Defining_Identifier
           (Map_C_Enumerator_Name
            (Parent_Subcomponent
             (P)));

         if Has_Ports (E) then
            F := First_Node (Features (E));

            while Present (F) loop
               if Kind (F) = K_Port_Spec_Instance then
                  if No (Backend_Node (Identifier (F))) or else
                    (Present (Backend_Node (Identifier (F))) and then
                     No (CTN.Local_Port_Node
                        (Backend_Node (Identifier (F))))) then

                     N := Make_Expression
                        (Make_Defining_Identifier
                           (Map_C_Enumerator_Name (F, Local_Port => True)),
                        Op_Equal,
                        (Make_Literal
                           (CV.New_Int_Value
                              (Local_Port_Identifier, 0, 10))));
                     Append_Node_To_List (N, Local_Port_List);

                     Append_Node_To_List
                     (Make_Defining_Identifier (Map_C_Enumerator_Name (F)),
                        CTN.Values (Local_Port_Values));
                     Bind_AADL_To_Local_Port
                        (Identifier (F), Local_Port_Values);

                     Nb_Ports_Total         := Nb_Ports_Total + 1;
                  end if;

                  Local_Port_Identifier  := Local_Port_Identifier + 1;
                  Nb_Ports_In_Process    := Nb_Ports_In_Process + 1;

                  if No (Backend_Node (Identifier (F))) or else
                    No (CTN.Global_Port_Node
                                 (Backend_Node (Identifier (F)))) then

                     N := (Make_Literal
                        (CV.New_Int_Value (0, 0, 10)));

                     Used_Bus := Get_Associated_Bus (F);

                     if Used_Bus /= No_Node then

                        if AAU.Is_Virtual_Bus (Used_Bus) then
                           Used_Bus := Parent_Component
                              (Parent_Subcomponent (Used_Bus));
                        end if;

                        Used_Device := Get_Device_Of_Process
                           (Used_Bus,
                              (Parent_Component
                                 (Parent_Subcomponent (E))));
                        if Used_Device /= No_Node then
                           N := Make_Defining_Identifier
                              (Map_C_Enumerator_Name
                                 (Corresponding_Instance (Used_Device)));
                        end if;
                     end if;

                     Append_Node_To_List (N, CTN.Values (Port_To_Devices));

                     N := Make_Defining_Identifier
                       (Map_C_Enumerator_Name (F, Local_Port => True));
                     Append_Node_To_List
                       (N, CTN.Values (Global_Port_To_Local));

                     N := Make_Defining_Identifier
                        (Map_C_Enumerator_Name
                           (S,
                           Entity => True,
                           Custom_Parent => Current_Device));
                     Append_Node_To_List
                       (N, CTN.Values (Global_Port_To_Entity));

                     N := Make_Literal
                        (CV.New_Pointed_Char_Value
                           (Map_C_Enumerator_Name
                              (F)));
                     Append_Node_To_List
                       (N, CTN.Values (Global_Port_Names));

                     N := Make_Literal
                        (CV.New_Pointed_Char_Value
                           (Display_Name (Identifier (F))));
                     Append_Node_To_List
                       (N, CTN.Values (Global_Port_Model_Names));

                     N := Make_Expression
                       (Make_Defining_Identifier
                        (Map_C_Enumerator_Name (F)),
                        Op_Equal,
                        (Make_Literal
                         (CV.New_Int_Value (Global_Port_Identifier, 0, 10))));
                     Append_Node_To_List (N, Global_Port_List);

                     Bind_AADL_To_Global_Port
                       (Identifier (F),
                        Make_Defining_Identifier
                        (Map_C_Enumerator_Name (F)));

                     Global_Port_Identifier := Global_Port_Identifier + 1;
                  end if;

               end if;

               F := Next_Node (F);
            end loop;

            if Parent_Component (Parent_Subcomponent (E))
               = Current_Process_Instance or else
               (Current_Device /= No_Node and then
               Get_Bound_Processor
                  (Current_Device) =
               Get_Bound_Processor (Current_Process_Instance)) then
               N := Make_Define_Statement
                  (Defining_Identifier =>
                     Make_Defining_Identifier
                        (Map_C_Define_Name (S, Nb_Ports => True)),
                  Value => Make_Literal
                     (New_Int_Value
                        (Local_Port_Identifier, 1, 10)));
               Append_Node_To_List (N, CTN.Declarations (Current_File));
            end if;
         end if;

         if Parent_Component (Parent_Subcomponent (E))
           = Current_Process_Instance and then
           not AAU.Is_Empty (Calls (E)) then
            Call_Seq := First_Node (Calls (E));

            while Present (Call_Seq) loop
               --  For each call sequence visit all the called
               --  subprograms.

               if not AAU.Is_Empty (Subprogram_Calls (Call_Seq)) then
                  Spg_Call := First_Node (Subprogram_Calls (Call_Seq));

                  while Present (Spg_Call) loop
                     Visit (Corresponding_Instance (Spg_Call));

                     Spg_Call := Next_Node (Spg_Call);
                  end loop;
               end if;

               Call_Seq := Next_Node (Call_Seq);
            end loop;
         end if;
      end Visit_Thread_Instance;

      -------------------------------
      -- Visit_Subprogram_Instance --
      -------------------------------

      procedure Visit_Subprogram_Instance (E : Node_Id) is
         N : Node_Id;
         S : constant Node_Id := Parent_Subcomponent (E);
      begin
         if Get_Subprogram_Kind (E) = Subprogram_Simulink then

            if Get_Source_Name (E) = No_Name then
               Display_Error
                  ("Simulink subprogram must have a"
                   & " source_name property",
                   Fatal => True);
            end if;

            if not (Present (Backend_Node (Identifier (S)))) or else
               (Present (Backend_Node (Identifier (S))) and then
               No (CTN.Naming_Node (Backend_Node (Identifier (S)))))
            then
               N := Make_Define_Statement
                  (Defining_Identifier =>
                     (RE (RE_Simulink_Node)),
                  Value => Make_Defining_Identifier
                           (Get_Source_Name (E)));
               Append_Node_To_List (N, CTN.Declarations (Current_File));

               N := Make_Define_Statement
                  (Defining_Identifier =>
                     (RE (RE_Simulink_Init_Func)),
                  Value => Map_Simulink_Init_Func (E));
               Append_Node_To_List (N, CTN.Declarations (Current_File));

               N := Make_Define_Statement
                  (Defining_Identifier =>
                     (RE (RE_Simulink_Model_Type)),
                  Value => Map_Simulink_Model_Type (E));
               Append_Node_To_List (N, CTN.Declarations (Current_File));

               Bind_AADL_To_Naming (Identifier (S), N);
            end if;

         end if;
      end Visit_Subprogram_Instance;

   end Header_File;

   -----------------
   -- Source_File --
   -----------------

   package body Source_File is

      procedure Visit_Architecture_Instance (E : Node_Id);
      procedure Visit_Component_Instance (E : Node_Id);
      procedure Visit_System_Instance (E : Node_Id);
      procedure Visit_Process_Instance (E : Node_Id);
      procedure Visit_Thread_Instance (E : Node_Id);

      -----------
      -- Visit --
      -----------

      procedure Visit (E : Node_Id) is
      begin
         case Kind (E) is
            when K_Architecture_Instance =>
               Visit_Architecture_Instance (E);

            when K_Component_Instance =>
               Visit_Component_Instance (E);

            when others =>
               null;
         end case;
      end Visit;

      ---------------------------------
      -- Visit_Architecture_Instance --
      ---------------------------------

      procedure Visit_Architecture_Instance (E : Node_Id) is
      begin
         Visit (Root_System (E));
      end Visit_Architecture_Instance;

      ------------------------------
      -- Visit_Component_Instance --
      ------------------------------

      procedure Visit_Component_Instance (E : Node_Id) is
         Category : constant Component_Category
           := Get_Category_Of_Component (E);
      begin
         case Category is
            when CC_System =>
               Visit_System_Instance (E);

            when CC_Process =>
               Visit_Process_Instance (E);

            when CC_Thread =>
               Visit_Thread_Instance (E);

            when others =>
               null;
         end case;
      end Visit_Component_Instance;

      ----------------------------
      -- Visit_Process_Instance --
      ----------------------------

      procedure Visit_Process_Instance (E : Node_Id) is
         U              : constant Node_Id := CTN.Distributed_Application_Unit
           (CTN.Naming_Node (Backend_Node (Identifier (E))));
         P              : constant Node_Id := CTN.Entity (U);
         S              : constant Node_Id := Parent_Subcomponent (E);
         N              : Node_Id;
         Q              : Node_Id;
         C              : Node_Id;
         Root_Sys       : constant Node_Id
                        := Parent_Component (Parent_Subcomponent (E));
         Endiannesses   : constant Node_Id := Make_Array_Values;
         Execution_Platform : Supported_Execution_Platform;
         Protected_Configuration : constant Node_Id := Make_Array_Values;
         Protected_Priorities    : constant Node_Id := Make_Array_Values;
         Protected_Protocol      : Node_Id;
         Protected_Priority      : Node_Id;
      begin
         Push_Entity (P);
         Push_Entity (U);
         Set_Deployment_Source;

         if not AAU.Is_Empty (Subcomponents (E)) then
            C := First_Node (Subcomponents (E));

            while Present (C) loop
               if AAU.Is_Data (Corresponding_Instance (C)) then
                  Protected_Priority :=
                     Make_Literal (New_Int_Value (0, 1, 10));

                  case Get_Concurrency_Protocol (Corresponding_Instance (C)) is
                     when Concurrency_Priority_Ceiling =>
                        Protected_Priority := Make_Literal
                           (New_Int_Value
                              (Get_Priority_Celing_Of_Data_Access
                                 (Corresponding_Instance (C)), 1, 10));
                        Protected_Protocol := RE (RE_Protected_PCP);

                     when Concurrency_Immediate_Priority_Ceiling =>
                        Protected_Protocol := RE (RE_Protected_IPCP);

                     when Concurrency_Priority_Inheritance =>
                        Protected_Protocol := RE (RE_Protected_PIP);

                     when others =>
                        Protected_Protocol := RE (RE_Protected_Regular);
                  end case;

                  Append_Node_To_List
                   (Protected_Protocol, CTN.Values (Protected_Configuration));

                  Append_Node_To_List
                     (Protected_Priority,
                     CTN.Values (Protected_Priorities));
               end if;

               Visit (Corresponding_Instance (C));
               C := Next_Node (C);
            end loop;
         end if;

         if not Is_Empty (CTN.Values (Protected_Configuration)) then
            N := Make_Expression
              (Left_Expr =>
                 Make_Variable_Declaration
                 (Defining_Identifier =>
                    Make_Array_Declaration
                    (Defining_Identifier =>
                       RE (RE_Protected_Configuration),
                     Array_Size =>
                       RE (RE_Nb_Protected)),
                  Used_Type =>
                    RE (RE_Protected_Protocol_T)),
               Operator => Op_Equal,
               Right_Expr => Protected_Configuration);
            Append_Node_To_List (N, CTN.Declarations (Current_File));

            N := Make_Expression
              (Left_Expr =>
                 Make_Variable_Declaration
                 (Defining_Identifier =>
                    Make_Array_Declaration
                    (Defining_Identifier =>
                       RE (RE_Protected_Priorities),
                     Array_Size =>
                       RE (RE_Nb_Protected)),
                  Used_Type =>
                    RE (RE_Uint8_T)),
               Operator => Op_Equal,
               Right_Expr => Protected_Priorities);
            Append_Node_To_List (N, CTN.Declarations (Current_File));
         end if;

         if Present (Backend_Node (Identifier (S))) and then
           Present (CTN.Global_Port_Node (Backend_Node (Identifier (S)))) then
            N := Make_Expression
              (Left_Expr =>
                 Make_Variable_Declaration
                 (Defining_Identifier =>
                    Make_Array_Declaration
                    (Defining_Identifier =>
                       RE (RE_Port_Global_To_Entity),
                     Array_Size =>
                       RE (RE_Nb_Ports)),
                  Used_Type =>
                    RE (RE_Entity_T)),
               Operator => Op_Equal,
               Right_Expr =>
                 CTN.Global_Port_Node (Backend_Node (Identifier (S))));
            Append_Node_To_List (N, CTN.Declarations (Current_File));
         end if;

         if Present (Backend_Node (Identifier (S))) and then
           Present (CTN.Global_Names_Node (Backend_Node (Identifier (S)))) then
            N := Make_Expression
              (Left_Expr =>
                 Make_Variable_Declaration
                 (Defining_Identifier =>
                    Make_Array_Declaration
                    (Defining_Identifier =>
                       RE (RE_Port_Global_Names),
                     Array_Size =>
                       RE (RE_Nb_Ports)),
                  Used_Type =>
                     CTU.Make_Pointer_Type
                        (New_Node (CTN.K_Char))),
               Operator => Op_Equal,
               Right_Expr =>
                 CTN.Global_Names_Node (Backend_Node (Identifier (S))));
            Append_Node_To_List (N, CTN.Declarations (Current_File));
         end if;

         if Present (Backend_Node (Identifier (S))) and then
           Present (CTN.Global_Model_Names_Node
            (Backend_Node (Identifier (S)))) then
            N := Make_Expression
              (Left_Expr =>
                 Make_Variable_Declaration
                 (Defining_Identifier =>
                    Make_Array_Declaration
                    (Defining_Identifier =>
                       RE (RE_Port_Global_Model_Names),
                     Array_Size =>
                       RE (RE_Nb_Ports)),
                  Used_Type =>
                      CTU.Make_Pointer_Type
                        (New_Node (CTN.K_Char))),
               Operator => Op_Equal,
               Right_Expr =>
                 CTN.Global_Model_Names_Node
                  (Backend_Node (Identifier (S))));
            Append_Node_To_List (N, CTN.Declarations (Current_File));
         end if;

         if Present (Backend_Node (Identifier (S))) and then
           Present (CTN.Local_Port_Node (Backend_Node (Identifier (S)))) then
            N := Make_Expression
              (Left_Expr =>
                 Make_Variable_Declaration
                 (Defining_Identifier =>
                    Make_Array_Declaration
                    (Defining_Identifier =>
                       RE (RE_Port_Global_To_Local),
                     Array_Size =>
                       RE (RE_Nb_Ports)),
                  Used_Type =>
                    RE (RE_Local_Port_T)),
               Operator => Op_Equal,
               Right_Expr =>
                 CTN.Local_Port_Node (Backend_Node (Identifier (S))));
            Append_Node_To_List (N, CTN.Declarations (Current_File));
         end if;

--         if Present (Backend_Node (Identifier (S))) and then
--           Present (CTN.Entities_Node (Backend_Node (Identifier (S)))) then
         N := Make_Expression
           (Left_Expr =>
              Make_Variable_Declaration
              (Defining_Identifier =>
                 Make_Array_Declaration
                 (Defining_Identifier =>
                     RE (RE_Entity_Table),
                  Array_Size =>
                    RE (RE_Nb_Entities)),
               Used_Type =>
                 RE (RE_Node_T)),
            Operator => Op_Equal,
            Right_Expr => Entity_Array);
--              CTN.Entities_Node (Backend_Node (Identifier (S))));
         Append_Node_To_List (N, CTN.Declarations (Current_File));
--         end if;

         Q := First_Node (Subcomponents (Root_Sys));

         while Present (Q) loop
            if AAU.Is_Process (Corresponding_Instance (Q)) and then
               Is_Added (Corresponding_Instance (Q), E) then
               Execution_Platform := Get_Execution_Platform
                  (Get_Bound_Processor
                     (Corresponding_Instance (Q)));
               case Execution_Platform is
                  when Platform_Native | Platform_None |
                       Platform_X86_RTEMS | Platform_X86_LINUXTASTE |
                       Platform_LINUX64 | Platform_LINUX32 =>
                     Append_Node_To_List
                        (RE (RE_Littleendian), CTN.Values (Endiannesses));

                  when Platform_LEON_RTEMS =>
                     Append_Node_To_List
                        (RE (RE_Bigendian), CTN.Values (Endiannesses));

                  when Platform_ARM_DSLINUX =>
                     Append_Node_To_List
                        (RE (RE_Bigendian), CTN.Values (Endiannesses));

                  when Platform_ARM_N770 =>
                     Append_Node_To_List
                        (RE (RE_Bigendian), CTN.Values (Endiannesses));

                  when others =>
                     Append_Node_To_List
                        (RE (RE_Bigendian), CTN.Values (Endiannesses));
                     Display_Error
                        ("Unknown endianess of " & Execution_Platform'Img,
                           Fatal => False);
               end case;
            end if;
            Q := Next_Node (Q);
         end loop;

         N := Make_Expression
           (Left_Expr =>
              Make_Variable_Declaration
              (Defining_Identifier =>
                 Make_Array_Declaration
                 (Defining_Identifier =>
                    RE (RE_Deployment_Endiannesses),
                  Array_Size =>
                    RE (RE_Nb_Nodes)),
               Used_Type =>
                 RE (RE_Uint8_T)),
            Operator => Op_Equal,
            Right_Expr => Endiannesses);
         Append_Node_To_List (N, CTN.Declarations (Current_File));

         if not Is_Empty (CTN.Values (Devices_Array)) then
            N := Make_Expression
              (Left_Expr =>
                 Make_Variable_Declaration
                 (Defining_Identifier =>
                    Make_Array_Declaration
                    (Defining_Identifier =>
                       RE (RE_Devices_Naming),
                     Array_Size =>
                       RE (RE_Nb_Devices)),
                  Used_Type =>
                    Make_Pointer_Type (New_Node (CTN.K_Char))),
               Operator => Op_Equal,
               Right_Expr => Devices_Array);
            Append_Node_To_List (N, CTN.Declarations (Current_File));
         end if;

         if not Is_Empty (CTN.Values (Port_To_Devices)) then
            N := Make_Expression
              (Left_Expr =>
                 Make_Variable_Declaration
                 (Defining_Identifier =>
                    Make_Array_Declaration
                    (Defining_Identifier =>
                       RE (RE_Port_To_Device),
                     Array_Size =>
                       RE (RE_Nb_Ports)),
                  Used_Type => RE (RE_Device_Id)),
               Operator => Op_Equal,
               Right_Expr => Port_To_Devices);
            Append_Node_To_List (N, CTN.Declarations (Current_File));
         end if;

         Pop_Entity; -- U
         Pop_Entity; -- P
      end Visit_Process_Instance;

      ---------------------------
      -- Visit_Thread_Instance --
      ---------------------------

      procedure Visit_Thread_Instance (E : Node_Id) is
         S        : constant Node_Id := Parent_Subcomponent (E);
         N        : Node_Id;
      begin
         if Present (Backend_Node (Identifier (S))) and then
           Present (CTN.Local_Port_Node (Backend_Node (Identifier (S)))) then
            N := Make_Expression
              (Left_Expr =>
                 Make_Variable_Declaration
                 (Defining_Identifier =>
                    Make_Array_Declaration
                    (Defining_Identifier =>
                       Make_Defining_Identifier
                       (Map_C_Variable_Name (S, Port_Variable => True)),
                     Array_Size =>
                       Make_Defining_Identifier
                       (Map_C_Define_Name (S, Nb_Ports => True))),
                  Used_Type =>
                    RE (RE_Port_T)),
               Operator => Op_Equal,
               Right_Expr =>
                 CTN.Local_Port_Node (Backend_Node (Identifier (S))));
            Append_Node_To_List (N, CTN.Declarations (Current_File));
         end if;
      end Visit_Thread_Instance;

      ---------------------------
      -- Visit_System_Instance --
      ---------------------------

      procedure Visit_System_Instance (E : Node_Id) is
         S : Node_Id;
      begin
         Push_Entity (C_Root);

         --  Visit all the subcomponents of the system

         if not AAU.Is_Empty (Subcomponents (E)) then
            S := First_Node (Subcomponents (E));
            while Present (S) loop
               --  Visit the component instance corresponding to the
               --  subcomponent S.

               Visit (Corresponding_Instance (S));
               S := Next_Node (S);
            end loop;
         end if;

         Pop_Entity; --  C_Root
      end Visit_System_Instance;

   end Source_File;

end Ocarina.Backends.PO_HI_C.Deployment;
