FROM registry.access.redhat.com/ubi8/go-toolset as builder

USER 0

WORKDIR /build

COPY main.go .

RUN go build -o demo main.go

FROM scratch

#USER 65534

COPY --from=builder /build/demo /demo

ENTRYPOINT ["/demo"]
