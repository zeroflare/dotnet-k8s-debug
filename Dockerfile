# 預設映像：一般 Release 執行，不含 vsdbg／PDB／curl。
# 遠端除錯請用 Dockerfile.debug。
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/NhiApi/NhiApi.csproj NhiApi/
RUN dotnet restore NhiApi/NhiApi.csproj

COPY src/NhiApi/ NhiApi/
WORKDIR /src/NhiApi
RUN dotnet publish -c Release \
    -o /app/publish \
    --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

COPY --from=build /app/publish .
RUN rm -f /app/*.pdb

ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production

EXPOSE 8080
ENTRYPOINT ["dotnet", "NhiApi.dll"]
