// this is in a separate file because of https://gitlab.com/freepascal.org/fpc/source/-/issues/41484 and https://gitlab.com/freepascal.org/fpc/source/-/issues/41485

generic function GetUpdatedFeature<T: TModelFeature>(ModelSystem: TModelSystem; Index: Integer = -1): T;
var
   UpdatedNodes: TAssetList;
   Asset: TModelAsset;
   Feature: TModelFeature;
begin
   Result := nil;
   UpdatedNodes := ModelSystem.GetUpdatedAssets();
   for Asset in UpdatedNodes do
   begin
      Feature := Asset.Features[T];
      if (Assigned(Feature)) then
      begin
         if (Index < 0) then
         begin
            if (Assigned(Result)) then
               raise Exception.CreateFmt('multiple updated nodes have requested feature (%s)', [T.ClassName]);
            Result := T(Feature); {as T}
         end
         else
         if (Index = 0) then
         begin
            Result := T(Feature); {as T}
            exit;
         end
         else
         begin
            Dec(Index);
         end;
      end;
   end;
   if (not Assigned(Result)) then
   begin
      Writeln('Updated assets:');
      for Asset in UpdatedNodes do
      begin
         Writeln(' + ', Asset.ToString(), ': ');
         if (Asset.FeatureCount > 0) then
         begin
            for Feature in Asset.GetFeatures() do
            begin
               Writeln('    - ', Feature.ToString());
            end;
         end
         else
            Writeln('     No features.');
      end;
      raise Exception.CreateFmt('could not find enough updated nodes with requested feature (%s)', [T.ClassName]);
   end;
   Verify(Assigned(Result));
end;
